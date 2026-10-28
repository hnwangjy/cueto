#if os(macOS)
import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let excludedApps = ExcludedAudioApps()
    private lazy var playback = PlaybackController(excludedApps: excludedApps)
    private let subtitles = CosmosSubtitleMonitor()
    private let appleLyrics = AppleMusicLyricsMonitor()
    private var subtitleStatusItem: NSStatusItem?
    private var subtitleObservations = Set<AnyCancellable>()
    private var statusItem: NSStatusItem?
    private var statusControlView: StatusBarControlView?
    private var statusItemObservation: AnyCancellable?
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private var settingsWindowController: NSWindowController?
    private var settingsModel: CuetoSettingsModel?
    private var notchPanelController: NotchPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        _ = updaterController
        notchPanelController = NotchPanelController(playback: playback, subtitles: subtitles, appleLyrics: appleLyrics) { [weak self] in
            self?.openCueto()
        }

        let item = NSStatusBar.system.statusItem(
            withLength: Self.statusItemLength(
                for: playback.applicationName,
                hasActiveSession: playback.hasActiveSession,
                sourceCount: playback.activeAudioSourceCount
            )
        )
        let controlView = StatusBarControlView(
            playback: playback,
            subtitles: subtitles,
            appleLyrics: appleLyrics,
            onOpenCueto: { [weak self] in self?.openCueto() },
            onQuit: { NSApplication.shared.terminate(nil) }
        )
        controlView.frame = NSRect(
            x: 0,
            y: 0,
            width: item.length,
            height: NSStatusBar.system.thickness
        )
        if let button = item.button {
            button.title = ""
            button.image = nil
            button.target = self
            button.action = #selector(statusItemActivated(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            (button.cell as? NSButtonCell)?.highlightsBy = []
            controlView.routesThroughStatusButton = true
            controlView.autoresizingMask = [.width, .height]
            controlView.frame = button.bounds
            button.addSubview(controlView)
            button.setAccessibilityLabel("Cueto 播放控制")
        }

        self.statusControlView = controlView
        self.statusItem = item
        subtitles.$currentText
            .combineLatest(appleLyrics.$currentText, subtitles.$width)
            .combineLatest(appleLyrics.$isPlaying, playback.$bundleIdentifier)
            .receive(on: RunLoop.main)
            .sink { [weak self] values, playing, source in
                self?.updateSubtitleItem(self?.appleLyrics.isEnabled == true && (playing || source == "com.apple.Music") ? values.1 : values.0, width: values.2.points)
            }
            .store(in: &subtitleObservations)
        statusItemObservation = playback.$applicationName
            .combineLatest(playback.$hasActiveSession, playback.$activeAudioSources)
            .sink { [weak item, weak controlView] name, hasActiveSession, sources in
                let length = Self.statusItemLength(
                    for: name,
                    hasActiveSession: hasActiveSession,
                    sourceCount: sources.count
                )
                item?.length = length
                controlView?.frame.size.width = length
            }
    }

    @objc private func statusItemActivated(_ sender: NSStatusBarButton) {
        statusControlView?.handleStatusItemEvent(NSApp.currentEvent)
    }

    private func updateSubtitleItem(_ text: String?, width: CGFloat) {
        guard let text, !text.isEmpty else {
            if let item = subtitleStatusItem { NSStatusBar.system.removeStatusItem(item) }
            subtitleStatusItem = nil
            return
        }
        let item: NSStatusItem
        if let existing = subtitleStatusItem {
            item = existing
        } else {
            item = NSStatusBar.system.statusItem(withLength: width)
            let view = SubtitleStatusView(frame: NSRect(x: 0, y: 0, width: width, height: NSStatusBar.system.thickness))
            view.target = self
            view.action = #selector(openSubtitleSettings)
            item.view = view
            subtitleStatusItem = item
        }
        item.length = width
        item.view?.setFrameSize(NSSize(width: width, height: NSStatusBar.system.thickness))
        (item.view as? SubtitleStatusView)?.show(text)
    }

    @objc private func openSubtitleSettings() { openCueto() }

    private static func statusItemLength(
        for applicationName: String,
        hasActiveSession: Bool = true,
        sourceCount: Int = 1
    ) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
        ]
        if !hasActiveSession {
            let idleNameWidth = ceil(("Cueto" as NSString).size(withAttributes: attributes).width)
            return 40 + idleNameWidth
        }
        let nameWidth = ceil((applicationName as NSString).size(withAttributes: attributes).width)
        let countWidth: CGFloat = sourceCount > 1 ? 18 : 0
        return min(max(136 + countWidth + nameWidth, 174), 246)
    }

    private func openCueto() {
        let model: CuetoSettingsModel
        let windowController: NSWindowController

        if let existingModel = settingsModel, let existingWindowController = settingsWindowController {
            model = existingModel
            windowController = existingWindowController
        } else {
            model = CuetoSettingsModel(updater: updaterController.updater)
            let rootView = CuetoSettingsView(model: model, excludedApps: excludedApps, subtitles: subtitles, appleLyrics: appleLyrics)
            let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
            window.title = "Cueto"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.level = .floating
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.setContentSize(NSSize(width: 500, height: 680))
            window.minSize = NSSize(width: 440, height: 540)
            window.isReleasedWhenClosed = false
            window.center()
            windowController = NSWindowController(window: window)
            settingsModel = model
            settingsWindowController = windowController
        }

        model.refresh()
        NSApplication.shared.activate(ignoringOtherApps: true)
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
        windowController.window?.orderFrontRegardless()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openCueto()
        return true
    }
}
#endif
