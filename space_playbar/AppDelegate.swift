#if os(macOS)
import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let excludedApps = ExcludedAudioApps()
    private lazy var playback = PlaybackController(excludedApps: excludedApps)
    private let subtitles = CosmosSubtitleMonitor()
    private let appleLyrics = AppleMusicLyricsMonitor()
    private let cosmosRecovery = CosmosCrashRecoveryMonitor()
    private var subtitleStatusItem: NSStatusItem?
    private var subtitleObservations = Set<AnyCancellable>()
    private var lastSubtitleContent: MenuBarSubtitleContent?
    private var lastSubtitleWidth: CGFloat?
    private var subtitleContinuity = MenuBarSubtitleContinuity()
    private var subtitleFallbackTask: Task<Void, Never>?
    private var scheduledSubtitleRefresh: Date?
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
        let updater = updaterController.updater
        if updater.automaticallyChecksForUpdates && updater.canCheckForUpdates {
            updater.checkForUpdatesInBackground()
        }
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
            button.setAccessibilityLabel(String(localized: "Cueto 播放控制"))
        }

        self.statusControlView = controlView
        self.statusItem = item
        Publishers.Merge3(subtitles.objectWillChange, appleLyrics.objectWillChange, playback.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshSubtitleItem() }
            .store(in: &subtitleObservations)
        refreshSubtitleItem()
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

    private func refreshSubtitleItem() {
        let source = playback.bundleIdentifier
        let showsApple = appleLyrics.isEnabled && (appleLyrics.isPlaying || source == "com.apple.Music")
        let showsCosmos = subtitles.isEnabled && (subtitles.currentText != nil || source == "app.podcast.cosmos")
        let content: MenuBarSubtitleContent?
        let identity: [String?]
        if showsApple {
            let title = appleLyrics.currentTrackTitle ?? (source == "com.apple.Music" ? playback.title : nil)
            let artist = appleLyrics.currentTrackArtist ?? (source == "com.apple.Music" ? playback.artist : nil)
            content = .make(lyric: appleLyrics.currentText,
                title: title, artist: artist,
                sourceIdentifier: "com.apple.Music", sourceName: "Apple Music",
                scrollTimeBudget: appleLyrics.currentLyricRemainingTime)
            identity = ["com.apple.Music", title, artist]
        } else if showsCosmos {
            let title = source == "app.podcast.cosmos" ? playback.title : nil
            let artist = source == "app.podcast.cosmos" ? playback.artist : nil
            content = .make(lyric: subtitles.currentText,
                title: title, artist: artist,
                sourceIdentifier: "app.podcast.cosmos", sourceName: String(localized: "小宇宙"))
            identity = ["app.podcast.cosmos", title, artist]
        } else {
            content = nil
            identity = []
        }
        let resolved = subtitleContinuity.resolve(content, trackIdentity: identity, at: Date(),
            hasEnteredLyrics: showsApple && (appleLyrics.lyricContext.previous != nil || appleLyrics.lyricContext.current != nil))
        if let deadline = subtitleContinuity.refreshAt {
            if scheduledSubtitleRefresh != deadline {
                subtitleFallbackTask?.cancel()
                scheduledSubtitleRefresh = deadline
                subtitleFallbackTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) }
                    catch { return }
                    guard let self, !Task.isCancelled else { return }
                    self.scheduledSubtitleRefresh = nil
                    self.refreshSubtitleItem()
                }
            }
        } else {
            subtitleFallbackTask?.cancel()
            subtitleFallbackTask = nil
            scheduledSubtitleRefresh = nil
        }
        updateSubtitleItem(resolved, width: subtitles.width.points)
    }

    private func updateSubtitleItem(_ content: MenuBarSubtitleContent?, width: CGFloat) {
        guard content != lastSubtitleContent || width != lastSubtitleWidth else { return }
        lastSubtitleContent = content
        lastSubtitleWidth = width
        guard let content else {
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
        (item.view as? SubtitleStatusView)?.show(content)
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
            return 48 + idleNameWidth
        }
        let nameWidth = ceil((applicationName as NSString).size(withAttributes: attributes).width)
        let countWidth: CGFloat = sourceCount > 1 ? 18 : 0
        return min(max(128 + countWidth + nameWidth, 164), 246)
    }

    private func openCueto() {
        let model: CuetoSettingsModel
        let windowController: NSWindowController

        if let existingModel = settingsModel, let existingWindowController = settingsWindowController {
            model = existingModel
            windowController = existingWindowController
        } else {
            model = CuetoSettingsModel(updater: updaterController.updater) { [weak self] in
                self?.settingsWindowController?.window?.level = .normal
            }
            let rootView = CuetoSettingsView(model: model, excludedApps: excludedApps, subtitles: subtitles, appleLyrics: appleLyrics, cosmosRecovery: cosmosRecovery)
            let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
            window.delegate = self
            window.title = "Cueto"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isOpaque = false
            window.backgroundColor = .windowBackgroundColor
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .visible
            window.level = .floating
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.setContentSize(NSSize(width: 780, height: 560))
            window.minSize = NSSize(width: 720, height: 520)
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

    func windowDidBecomeKey(_ notification: Notification) {
        settingsWindowController?.window?.level = .floating
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openCueto()
        return true
    }
}
#endif
