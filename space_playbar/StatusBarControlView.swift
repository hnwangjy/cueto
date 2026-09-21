#if os(macOS)
import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarControlView: NSView, NSPopoverDelegate {
    private let playback: PlaybackController
    private let onOpenCueto: () -> Void
    private let onQuit: () -> Void
    private var observations = Set<AnyCancellable>()
    private var popover: NSPopover?
    private let separator = NSBox()
    private var sourceWidthConstraint: NSLayoutConstraint?
    private var isCompact = false
    private var pendingSourceRefresh: DispatchWorkItem?

    private lazy var sourceButton = makeButton(action: #selector(showNowPlaying))
    private lazy var backwardButton = makeSymbolButton(
        symbol: "backward.end",
        label: "上一首",
        action: #selector(goBackward)
    )
    private lazy var playPauseButton = makeSymbolButton(
        symbol: "play.fill",
        label: "播放",
        action: #selector(togglePlayback)
    )
    private lazy var forwardButton = makeSymbolButton(
        symbol: "forward.end",
        label: "下一首",
        action: #selector(goForward)
    )

    init(
        playback: PlaybackController,
        onOpenCueto: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.playback = playback
        self.onOpenCueto = onOpenCueto
        self.onQuit = onQuit
        super.init(frame: .zero)
        setupView()
        observePlayback()
        refreshSource()
        refreshPlaybackState()
        refreshAvailability()
        refreshLayoutMode()
        refreshAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var allowsVibrancy: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: "打开 Cueto", action: #selector(openCueto), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Cueto", action: #selector(quitCueto), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func setupView() {
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        sourceButton.kind = .source
        sourceButton.toolTip = "查看当前播放来源"
        sourceButton.setAccessibilityLabel("当前播放来源")
        sourceButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sourceButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [
            sourceButton,
            separator,
            backwardButton,
            playPauseButton,
            forwardButton
        ])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let sourceWidthConstraint = sourceButton.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -80)
        self.sourceWidthConstraint = sourceWidthConstraint
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.heightAnchor.constraint(equalToConstant: 14),
            sourceWidthConstraint,
            sourceButton.heightAnchor.constraint(equalTo: heightAnchor),
            backwardButton.widthAnchor.constraint(equalToConstant: 25),
            backwardButton.heightAnchor.constraint(equalToConstant: 18),
            playPauseButton.widthAnchor.constraint(equalToConstant: 25),
            playPauseButton.heightAnchor.constraint(equalToConstant: 18),
            forwardButton.widthAnchor.constraint(equalToConstant: 25),
            forwardButton.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    private func makeButton(action: Selector) -> StatusBarNativeButton {
        let button = StatusBarNativeButton()
        button.isBordered = false
        button.bezelStyle = .inline
        button.setButtonType(.momentaryPushIn)
        button.target = self
        button.action = action
        button.focusRingType = .none
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func makeSymbolButton(symbol: String, label: String, action: Selector) -> StatusBarNativeButton {
        let button = makeButton(action: action)
        button.kind = .symbol(symbol)
        button.toolTip = label
        button.setAccessibilityLabel(label)
        return button
    }

    private func observePlayback() {
        playback.$applicationName
            .combineLatest(playback.$applicationIcon)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.scheduleSourceRefresh() }
            .store(in: &observations)

        playback.$bundleIdentifier
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshTransportControls()
                self?.scheduleSourceRefresh()
            }
            .store(in: &observations)

        playback.$isPlaying
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshPlaybackState() }
            .store(in: &observations)

        playback.$hasActiveSession
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshAvailability()
                self?.refreshLayoutMode()
            }
            .store(in: &observations)

        playback.$activeAudioSources
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.scheduleSourceRefresh() }
            .store(in: &observations)
    }

    private func scheduleSourceRefresh() {
        pendingSourceRefresh?.cancel()
        let refresh = DispatchWorkItem { [weak self] in self?.refreshSource() }
        pendingSourceRefresh = refresh
        DispatchQueue.main.async(execute: refresh)
    }

    private func refreshSource() {
        let image: NSImage?
        if let icon = playback.applicationIcon {
            image = icon.copy() as? NSImage
            image?.size = NSSize(width: 15, height: 15)
        } else {
            image = nil
        }
        sourceButton.updateSource(
            title: playback.applicationName,
            image: image,
            identifier: playback.bundleIdentifier,
            count: playback.activeAudioSourceCount
        )
        refreshAppearance()
    }

    private func refreshLayoutMode() {
        let compact = !playback.hasActiveSession
        guard compact != isCompact else { return }
        isCompact = compact
        separator.isHidden = compact
        backwardButton.isHidden = compact
        playPauseButton.isHidden = compact
        forwardButton.isHidden = compact
        sourceWidthConstraint?.constant = compact ? 0 : -80
        sourceButton.compactAppIconOnly = compact
        sourceButton.toolTip = compact ? "打开 Cueto" : "查看当前播放来源"
        sourceButton.setAccessibilityLabel(compact ? "打开 Cueto" : "当前播放来源")
        needsLayout = true
    }

    private func refreshPlaybackState() {
        let isPlaying = playback.isPlaying
        let label = isPlaying ? "暂停" : "播放"
        playPauseButton.kind = .symbol(isPlaying ? "pause.fill" : "play.fill")
        playPauseButton.toolTip = label
        playPauseButton.setAccessibilityLabel(label)
        refreshAppearance()
    }

    private func refreshAppearance() {
        let foregroundColor = NSColor.white
        let separatorColor = NSColor.white.withAlphaComponent(0.32)

        [sourceButton, backwardButton, playPauseButton, forwardButton].forEach {
            $0.foregroundColor = foregroundColor
        }
        separator.fillColor = separatorColor
        needsDisplay = true
    }

    private func refreshTransportControls() {
        update(button: backwardButton, label: playback.backwardControlLabel)
        update(button: forwardButton, label: playback.forwardControlLabel)
    }

    private func update(button: StatusBarNativeButton, label: String) {
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }

    private func refreshAvailability() {
        let isAvailable = playback.hasActiveSession
        [sourceButton, backwardButton, playPauseButton, forwardButton].forEach {
            $0.isEnabled = isAvailable
        }
        alphaValue = isAvailable ? 1 : 0.62
    }

    @objc private func showNowPlaying() {
        guard playback.hasActiveSession else {
            onOpenCueto()
            return
        }
        if let popover, popover.isShown {
            sourceButton.showsSelection = false
            popover.performClose(nil)
            self.popover = nil
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: NowPlayingPopover(
                playback: playback,
                onOpenCueto: { [weak self] in
                    self?.popover?.performClose(nil)
                    self?.onOpenCueto()
                },
                onQuit: { [weak self] in self?.onQuit() }
            )
            .environment(\.controlActiveState, .active)
        )
        self.popover = popover
        sourceButton.showsSelection = true
        popover.show(relativeTo: sourceButton.bounds, of: sourceButton, preferredEdge: .minY)
        activate(popover: popover)
        DispatchQueue.main.async { [weak self, weak popover] in
            guard let self, let popover else { return }
            self.activate(popover: popover)
        }
    }

    private func activate(popover: NSPopover) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        sourceButton.showsSelection = false
        popover = nil
    }

    @objc private func goBackward() {
        playback.goBackward()
    }

    @objc private func togglePlayback() {
        playback.playPause()
    }

    @objc private func goForward() {
        playback.goForward()
    }

    @objc private func openCueto() {
        onOpenCueto()
    }

    @objc private func quitCueto() {
        onQuit()
    }
}

private final class StatusBarNativeButton: NSButton {
    private struct SourcePresentation {
        let title: String
        let image: NSImage?
        let identifier: String?
    }

    enum Kind {
        case source
        case symbol(String)
    }

    var kind: Kind = .source {
        didSet { needsDisplay = true }
    }
    var statusTitle = "" {
        didSet { needsDisplay = true }
    }
    var statusImage: NSImage? {
        didSet { needsDisplay = true }
    }
    var sourceCount = 0 {
        didSet { needsDisplay = true }
    }
    var compactAppIconOnly = false {
        didSet { needsDisplay = true }
    }
    var foregroundColor = NSColor.white {
        didSet { needsDisplay = true }
    }
    var showsSelection = false {
        didSet { needsDisplay = true }
    }
    private var isPressing = false
    private var displayedSource: SourcePresentation?
    private var outgoingSource: SourcePresentation?
    private var sourceTransitionProgress: CGFloat = 1
    private var sourceTransitionTimer: Timer?
    private var sourceTransitionStartedAt = Date()
    private let sourceTransitionDuration: TimeInterval = 0.22

    deinit {
        sourceTransitionTimer?.invalidate()
    }

    func updateSource(title: String, image: NSImage?, identifier: String?, count: Int) {
        sourceCount = count
        statusTitle = title
        statusImage = image

        let incoming = SourcePresentation(title: title, image: image, identifier: identifier)
        guard let current = displayedSource else {
            displayedSource = incoming
            needsDisplay = true
            return
        }

        guard current.identifier != identifier else {
            displayedSource = incoming
            needsDisplay = true
            return
        }

        sourceTransitionTimer?.invalidate()
        outgoingSource = current
        displayedSource = incoming

        guard current.identifier != nil,
              identifier != nil,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            outgoingSource = nil
            sourceTransitionProgress = 1
            needsDisplay = true
            return
        }

        sourceTransitionProgress = 0
        sourceTransitionStartedAt = Date()
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            let elapsed = Date().timeIntervalSince(self.sourceTransitionStartedAt)
            let linearProgress = min(max(elapsed / self.sourceTransitionDuration, 0), 1)
            self.sourceTransitionProgress = CGFloat(1 - pow(1 - linearProgress, 3))
            self.needsDisplay = true
            if linearProgress >= 1 {
                timer.invalidate()
                self.outgoingSource = nil
            }
        }
        sourceTransitionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        isPressing = true
        needsDisplay = true
        displayIfNeeded()
        super.mouseDown(with: event)
        isPressing = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if showsSelection || isPressing || cell?.isHighlighted == true {
            let highlightRect: NSRect
            let highlightOpacity: CGFloat
            switch kind {
            case .source:
                highlightRect = bounds.insetBy(dx: 0, dy: 0.5)
                highlightOpacity = 0.30
            case .symbol:
                highlightRect = bounds.insetBy(dx: 2, dy: 2)
                highlightOpacity = 0.18
            }
            foregroundColor.withAlphaComponent(highlightOpacity).setFill()
            let cornerRadius: CGFloat
            switch kind {
            case .source: cornerRadius = 7
            case .symbol: cornerRadius = 5
            }
            NSBezierPath(roundedRect: highlightRect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        }

        let opacity: CGFloat = isEnabled ? 1 : 0.48
        switch kind {
        case .source:
            drawSource(opacity: opacity)
        case let .symbol(name):
            drawSymbol(name, pointSize: 13, opacity: opacity, centeredIn: bounds)
        }
    }

    private func drawSource(opacity: CGFloat) {
        if compactAppIconOnly {
            let appIcon = NSApplication.shared.applicationIconImage
            let iconRect = NSRect(x: bounds.midX - 9, y: bounds.midY - 9, width: 18, height: 18)
            appIcon?.draw(
                in: iconRect,
                from: .zero,
                operation: .sourceOver,
                fraction: opacity,
                respectFlipped: true,
                hints: nil
            )
            return
        }

        let countWidth: CGFloat = sourceCount > 1 ? 19 : 0
        if sourceCount > 1 {
            let symbolName = sourceCount <= 9 ? "\(sourceCount).circle.fill" : "9.plus.circle.fill"
            let countRect = NSRect(x: 3, y: floor((bounds.height - 16) / 2), width: 16, height: 16)
            drawSymbol(
                symbolName,
                pointSize: 14,
                opacity: opacity,
                color: .controlAccentColor,
                centeredIn: countRect
            )
        }

        let progress = sourceTransitionProgress
        if let outgoingSource, progress < 1 {
            drawSourceIdentity(
                outgoingSource,
                countWidth: countWidth,
                xOffset: -16 * progress,
                opacity: opacity * (1 - progress)
            )
        }
        if let displayedSource {
            let isTransitioning = outgoingSource != nil && progress < 1
            drawSourceIdentity(
                displayedSource,
                countWidth: countWidth,
                xOffset: isTransitioning ? 18 * (1 - progress) : 0,
                opacity: opacity * (isTransitioning ? progress : 1)
            )
        }

        let chevronRect = NSRect(x: bounds.maxX - 12, y: floor((bounds.height - 8) / 2), width: 7, height: 8)
        drawSymbol("chevron.down", pointSize: 7, opacity: opacity * 0.72, centeredIn: chevronRect)
    }

    private func drawSourceIdentity(
        _ source: SourcePresentation,
        countWidth: CGFloat,
        xOffset: CGFloat,
        opacity: CGFloat
    ) {
        let iconRect = NSRect(
            x: 5 + countWidth + xOffset,
            y: floor((bounds.height - 15) / 2),
            width: 15,
            height: 15
        )
        if let image = source.image {
            image.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: opacity, respectFlipped: true, hints: nil)
        } else {
            drawSymbol("waveform", pointSize: 12, opacity: opacity, centeredIn: iconRect)
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let textRect = NSRect(
            x: 24 + countWidth + xOffset,
            y: floor((bounds.height - 16) / 2),
            width: max(bounds.width - 40 - countWidth, 0),
            height: 16
        )
        (source.title as NSString).draw(
            with: textRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: foregroundColor.withAlphaComponent(opacity),
                .paragraphStyle: paragraph
            ]
        )
    }

    private func drawSymbol(
        _ name: String,
        pointSize: CGFloat,
        opacity: CGFloat,
        color: NSColor? = nil,
        centeredIn rect: NSRect
    ) {
        let baseConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        let colorConfiguration = NSImage.SymbolConfiguration(
            hierarchicalColor: (color ?? foregroundColor).withAlphaComponent(opacity)
        )
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(baseConfiguration.applying(colorConfiguration)) else { return }
        let size = image.size
        let imageRect = NSRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
#endif
