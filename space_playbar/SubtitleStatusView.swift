#if os(macOS)
import AppKit
import QuartzCore

/// A stable-width menu-bar lyric line with one consistent fade transition.
@MainActor
final class SubtitleStatusView: NSButton {
    private var content: MenuBarSubtitleContent?
    private var textContainer: CALayer?
    private var primaryText: CATextLayer?
    private var scrollPlan: SubtitleScrollPlan?
    private var scrollBeganAt: CFTimeInterval?
    private var frozenReadingOffset: CGFloat = 0
    private var contentReceivedAt: CFTimeInterval = 0
    private var scrollTimer: Timer?
    private static let textFont = NSFont.systemFont(ofSize: 13, weight: .bold)
    private static let horizontalInset: CGFloat = 4

    private static func textWidth(for text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: textFont]).width) + 2
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        title = ""
        isBordered = false
        wantsLayer = true
        layer?.masksToBounds = true
        setAccessibilityLabel(String(localized: "当前字幕或歌词"))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {}

    override func setFrameSize(_ newSize: NSSize) {
        let offset = readingOffset
        let changed = frame.size != newSize
        super.setFrameSize(newSize)
        if changed { render(transition: false, offset: offset) }
    }

    func show(_ next: MenuBarSubtitleContent) {
        guard content != next else { return }
        let extendsCurrentLine = content.map {
            !$0.isMetadata && !$0.text.isEmpty && !next.isMetadata && $0.sourceIdentifier == next.sourceIdentifier && next.text.hasPrefix($0.text)
        } ?? false
        let offset = extendsCurrentLine ? readingOffset : 0
        content = next
        contentReceivedAt = CACurrentMediaTime()
        toolTip = next.text
        setAccessibilityValue(next.text)
        render(transition: !extendsCurrentLine, offset: offset)
    }

    private var readingOffset: CGFloat {
        guard let plan = scrollPlan, let beganAt = scrollBeganAt else { return frozenReadingOffset }
        return CGFloat(plan.offset(at: CACurrentMediaTime() - beganAt))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            frozenReadingOffset = readingOffset
            scrollBeganAt = nil
            scrollTimer?.invalidate()
            scrollTimer = nil
            textContainer?.removeAllAnimations()
            primaryText?.removeAllAnimations()
        } else {
            render(transition: false, offset: readingOffset)
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        render(transition: false, offset: readingOffset)
    }

    private func render(transition: Bool, offset: CGFloat = 0) {
        guard let layer, let content else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scrollTimer?.invalidate()
        scrollTimer = nil
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let container = CALayer()
        container.frame = bounds.insetBy(dx: Self.horizontalInset, dy: 0)
        container.masksToBounds = true
        let viewport = max(0, container.bounds.width)
        let width = Self.textWidth(for: content.text)
        let overflow = width > viewport
        let scrolls = overflow && !reduced && !content.isMetadata
        scrollPlan = nil
        scrollBeganAt = nil
        frozenReadingOffset = 0
        let text = CATextLayer()
        text.contentsScale = window?.backingScaleFactor ?? 2
        text.string = NSAttributedString(string: content.text, attributes: [
            .font: Self.textFont, .foregroundColor: NSColor.white
        ])
        let height = ceil(Self.textFont.ascender - Self.textFont.descender + 2)
        let y = (((container.bounds.height - height) / 2 + 1) * text.contentsScale).rounded() / text.contentsScale
        text.frame = CGRect(x: overflow ? 0 : floor((viewport - width) / 2), y: y,
                            width: scrolls ? width : min(width, viewport), height: height)
        text.truncationMode = scrolls ? .none : .end
        container.addSublayer(text)

        if scrolls {
            let now = CACurrentMediaTime()
            let budget = content.scrollTimeBudget.map { max(0, $0 - (now - contentReceivedAt)) }
            let plan = SubtitleScrollPlan(travel: Double(width - viewport), offset: Double(offset), availableTime: budget)
            scrollPlan = plan
            scrollBeganAt = window == nil ? nil : now
            frozenReadingOffset = CGFloat(plan.start)
            // The model always contains the visible position. Never pre-set it
            // to the final offset and rely on a presentation animation to hide it.
            text.transform = CATransform3DMakeTranslation(-CGFloat(plan.start), 0, 0)
            let mask = CAGradientLayer()
            mask.frame = container.bounds
            mask.startPoint = CGPoint(x: 0, y: 0.5)
            mask.endPoint = CGPoint(x: 1, y: 0.5)
            let edge = min(0.08, 8 / max(viewport, 1))
            mask.locations = [0, NSNumber(value: edge), NSNumber(value: 1 - edge), 1]
            mask.colors = readingEdgeColors(offset: plan.start, end: plan.end)
            container.mask = mask
        }

        // Replace the old text immediately, then fade in the new one. Keeping
        // two differently sized lines on screen creates overlap and false motion.
        textContainer?.removeFromSuperlayer()
        layer.addSublayer(container)
        textContainer = container
        primaryText = text
        CATransaction.commit()
        if let plan = scrollPlan, plan.duration > 0, window != nil {
            let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] timer in
                MainActor.assumeIsolated {
                    guard let self, let plan = self.scrollPlan, self.window != nil else {
                        timer.invalidate()
                        return
                    }
                    let offset = self.readingOffset
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    self.primaryText?.transform = CATransform3DMakeTranslation(-offset, 0, 0)
                    (self.textContainer?.mask as? CAGradientLayer)?.colors = self.readingEdgeColors(offset: Double(offset), end: plan.end)
                    CATransaction.commit()
                    if Double(offset) >= plan.end {
                        timer.invalidate()
                        self.frozenReadingOffset = CGFloat(plan.end)
                        self.scrollBeganAt = nil
                        self.scrollTimer = nil
                    }
                }
            }
            timer.fireDate = Date().addingTimeInterval(plan.hold)
            scrollTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        if transition {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.55
            fade.toValue = 1
            fade.duration = 0.12
            container.add(fade, forKey: "sentenceFadeIn")
        }
    }
    private func readingEdgeColors(offset: Double, end: Double) -> [CGColor] {
        let black = NSColor.black.cgColor
        let leftAlpha = 1 - min(1, max(0, offset) / 8)
        let rightAlpha = 1 - min(1, max(0, end - offset) / 8)
        return [CGColor(gray: 0, alpha: leftAlpha), black, black, CGColor(gray: 0, alpha: rightAlpha)]
    }

}
#endif
