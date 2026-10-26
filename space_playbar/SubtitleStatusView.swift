#if os(macOS)
import AppKit
import QuartzCore

/// Fixed menu-bar footprint; only the text layers move.
@MainActor
final class SubtitleStatusView: NSButton {
    private var currentText = ""
    private var textContainer: CALayer?
    private var primaryText: CATextLayer?
    private let textFont = NSFont.systemFont(ofSize: 12, weight: .medium)

    override init(frame: NSRect) {
        super.init(frame: frame)
        title = ""
        isBordered = false
        wantsLayer = true
        layer?.masksToBounds = true
        setAccessibilityLabel("小宇宙字幕")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {}

    override func setFrameSize(_ newSize: NSSize) {
        let offset = readingOffset
        let changed = frame.size != newSize
        super.setFrameSize(newSize)
        if changed { render(transition: false, offset: offset) }
    }

    func show(_ text: String) {
        guard currentText != text else { return }
        // Growing the same sentence should continue from the visible words.
        if !currentText.isEmpty, text.hasPrefix(currentText) {
            let offset = readingOffset
            currentText = text
            toolTip = text
            setAccessibilityValue(text)
            render(transition: false, offset: offset)
            return
        }
        // The panel and menu bar must advance on the same source update.
        // Never postpone the next sentence to finish a previous scroll.
        present(text)
    }

    private var readingOffset: CGFloat {
        guard let text = primaryText else { return 0 }
        return max(0, -(text.presentation() ?? text).transform.m41)
    }

    private func present(_ text: String) {
        currentText = text
        toolTip = text
        setAccessibilityValue(text)
        render(transition: true)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            layer?.sublayers?.forEach { $0.removeAllAnimations() }
            textContainer?.sublayers?.forEach { $0.removeAllAnimations() }
        } else {
            render(transition: false, offset: readingOffset)
        }
    }

    private func render(transition: Bool, offset: CGFloat = 0) {
        guard let layer, !currentText.isEmpty else { return }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // An interrupted sentence transition must not leave outgoing layers behind.
        layer.sublayers?.filter { $0 !== textContainer }.forEach { $0.removeFromSuperlayer() }
        let outgoing = textContainer
        let container = CALayer()
        container.frame = bounds.insetBy(dx: 6, dy: 0)
        container.masksToBounds = true
        let viewport = container.bounds.width
        let width = ceil((currentText as NSString).size(withAttributes: [.font: textFont]).width) + 2
        let overflow = width > viewport
        let height = ceil(textFont.ascender - textFont.descender + 2)

        func makeText(x: CGFloat) -> CATextLayer {
            let text = CATextLayer()
            text.contentsScale = window?.backingScaleFactor ?? 2
            text.string = NSAttributedString(string: currentText, attributes: [
                .font: textFont, .foregroundColor: NSColor.white
            ])
            text.frame = CGRect(x: x, y: floor((bounds.height - height) / 2),
                                width: reduced ? min(width, viewport) : width, height: height)
            text.truncationMode = reduced ? .end : .none
            return text
        }
        let primary = makeText(x: overflow ? 0 : floor((viewport - width) / 2))
        primaryText = primary
        container.addSublayer(primary)
        if overflow && !reduced {
            let travel = max(0, width - viewport)
            let start = min(offset, travel)
            let remaining = travel - start
            let hold: Double = start > 0 ? 0 : 0.15
            // Only reveal the overflow, then leave the final words stationary.
            let speed: CGFloat = viewport < 200 ? 62 : 52
            let duration = remaining > 0 ? max(0.25, Double(remaining / speed)) : 0
            primary.transform = CATransform3DMakeTranslation(-travel, 0, 0)
            if remaining > 0 {
                let scroll = CAKeyframeAnimation(keyPath: "transform.translation.x")
                scroll.values = [-start, -start, -travel]
                scroll.keyTimes = [0, NSNumber(value: hold / (hold + duration)), 1]
                scroll.duration = hold + duration
                scroll.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(controlPoints: 0.12, 0.2, 0.8, 1)]
                primary.add(scroll, forKey: "subtitleScroll")
            }
            let fade = CAGradientLayer()
            fade.frame = container.bounds
            fade.startPoint = CGPoint(x: 0, y: 0.5)
            fade.endPoint = CGPoint(x: 1, y: 0.5)
            fade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
            fade.locations = [0, 0.025, 0.975, 1]
            container.mask = fade
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.addSublayer(container)
        textContainer = container
        CATransaction.commit()
        guard transition, let outgoing else { outgoing?.removeFromSuperlayer(); return }
        let duration = 0.18
        CATransaction.begin()
        CATransaction.setCompletionBlock { outgoing.removeFromSuperlayer() }
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1
        fadeIn.duration = duration
        container.add(fadeIn, forKey: "sentenceFadeIn")
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1
        fadeOut.toValue = 0
        fadeOut.duration = duration
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false
        outgoing.add(fadeOut, forKey: "sentenceFadeOut")
        if !reduced {
            for (target, from, to) in [(container, CGFloat(-5), CGFloat(0)), (outgoing, CGFloat(0), CGFloat(5))] {
                let slide = CABasicAnimation(keyPath: "transform.translation.y")
                slide.fromValue = from
                slide.toValue = to
                slide.duration = duration
                slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
                target.add(slide, forKey: "sentenceSlide")
            }
        }
        CATransaction.commit()
    }
}
#endif
