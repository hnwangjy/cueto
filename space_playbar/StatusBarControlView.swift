#if os(macOS)
import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarControlView: NSView {
    private let playback: PlaybackController
    private let onOpenCueto: () -> Void
    private let onQuit: () -> Void
    private var observations = Set<AnyCancellable>()
    private var popover: NSPopover?
    private let separator = NSBox()

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

        sourceButton.imagePosition = .imageLeading
        sourceButton.imageScaling = .scaleProportionallyDown
        sourceButton.font = .systemFont(ofSize: 12, weight: .semibold)
        sourceButton.alignment = .center
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
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.heightAnchor.constraint(equalToConstant: 14),
            backwardButton.widthAnchor.constraint(equalToConstant: 25),
            playPauseButton.widthAnchor.constraint(equalToConstant: 25),
            forwardButton.widthAnchor.constraint(equalToConstant: 25)
        ])
    }

    private func makeButton(action: Selector) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.bezelStyle = .inline
        button.setButtonType(.momentaryPushIn)
        button.target = self
        button.action = action
        button.focusRingType = .none
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func makeSymbolButton(symbol: String, label: String, action: Selector) -> NSButton {
        let button = makeButton(action: action)
        button.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: label
        )?.withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = label
        button.setAccessibilityLabel(label)
        return button
    }

    private func observePlayback() {
        playback.$applicationName
            .combineLatest(playback.$applicationIcon)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.refreshSource() }
            .store(in: &observations)

        playback.$bundleIdentifier
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshTransportControls() }
            .store(in: &observations)

        playback.$isPlaying
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshPlaybackState() }
            .store(in: &observations)

        playback.$hasActiveSession
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshAvailability() }
            .store(in: &observations)
    }

    private func refreshSource() {
        if let icon = playback.applicationIcon {
            let image = icon.copy() as? NSImage
            image?.size = NSSize(width: 15, height: 15)
            sourceButton.image = image
        } else {
            sourceButton.image = NSImage(
                systemSymbolName: "waveform",
                accessibilityDescription: "播放来源"
            )?.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        }
        refreshAppearance()
    }

    private func refreshPlaybackState() {
        let isPlaying = playback.isPlaying
        let label = isPlaying ? "暂停" : "播放"
        playPauseButton.image = NSImage(
            systemSymbolName: isPlaying ? "pause.fill" : "play.fill",
            accessibilityDescription: label
        )?.withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        playPauseButton.toolTip = label
        playPauseButton.setAccessibilityLabel(label)
        refreshAppearance()
    }

    private func refreshAppearance() {
        let foregroundColor = NSColor.white
        let separatorColor = NSColor.white.withAlphaComponent(0.32)

        sourceButton.attributedTitle = NSAttributedString(
            string: "\(playback.applicationName) ⌄",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: foregroundColor
            ]
        )
        [sourceButton, backwardButton, playPauseButton, forwardButton].forEach {
            $0.contentTintColor = foregroundColor
        }
        separator.fillColor = separatorColor
        needsDisplay = true
    }

    private func refreshTransportControls() {
        update(button: backwardButton, label: playback.backwardControlLabel)
        update(button: forwardButton, label: playback.forwardControlLabel)
    }

    private func update(button: NSButton, label: String) {
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
        if let popover, popover.isShown {
            popover.performClose(nil)
            self.popover = nil
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: NowPlayingPopover(
                playback: playback,
                onOpenCueto: { [weak self] in
                    self?.popover?.performClose(nil)
                    self?.onOpenCueto()
                },
                onQuit: { [weak self] in self?.onQuit() }
            )
        )
        self.popover = popover
        popover.show(relativeTo: sourceButton.bounds, of: sourceButton, preferredEdge: .minY)
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
#endif
