#if os(macOS)
import AppKit
import Combine
import Sparkle
import SwiftUI
#if DEBUG
import Darwin
import OSLog
#endif

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let excludedApps = ExcludedAudioApps()
    private lazy var playback = PlaybackController(excludedApps: excludedApps)
    private lazy var subtitles = CosmosSubtitleMonitor()
    private lazy var appleLyrics = AppleMusicLyricsMonitor()
    private lazy var cosmosRecovery = CosmosCrashRecoveryMonitor()
#if DEBUG
    // Keep the descriptor open for the process lifetime. macOS releases the
    // lock on exit, including when Xcode stops the debug session.
    private var developmentInstanceLock: Int32 = -1
#endif
    private var subtitleStatusView: SubtitleStatusView?
    private var subtitleObservations = Set<AnyCancellable>()
    private var lastSubtitleContent: MenuBarSubtitleContent?
    private var lastSubtitleWidth: CGFloat?
    private var subtitleContinuity = MenuBarSubtitleContinuity()
    private var subtitleFallbackTask: Task<Void, Never>?
    private var scheduledSubtitleRefresh: Date?
    private var statusItem: NSStatusItem?
    private var statusControlView: StatusBarControlView?
    private var statusControlWidth: CGFloat = 0
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
#if DEBUG
        guard claimDevelopmentInstance() else {
            NSApplication.shared.terminate(nil)
            return
        }
#endif
        NSApplication.shared.setActivationPolicy(.accessory)
        _ = cosmosRecovery
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
            controlView.frame = button.bounds
            button.addSubview(controlView)
            button.setAccessibilityLabel(String(localized: "Cueto 播放控制"))
        }

        self.statusControlView = controlView
        self.statusControlWidth = item.length
        self.statusItem = item
        Publishers.Merge3(subtitles.objectWillChange, appleLyrics.objectWillChange, playback.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshSubtitleItem() }
            .store(in: &subtitleObservations)
        refreshSubtitleItem()
        statusItemObservation = playback.$applicationName
            .combineLatest(playback.$hasActiveSession, playback.$activeAudioSources)
            .sink { [weak self] name, hasActiveSession, sources in
                guard let self else { return }
                self.statusControlWidth = Self.statusItemLength(
                    for: name,
                    hasActiveSession: hasActiveSession,
                    sourceCount: sources.count
                )
                self.layoutStatusItem()
            }
    }

#if DEBUG
    private func claimDevelopmentInstance() -> Bool {
        guard let identifier = Bundle.main.bundleIdentifier else { return true }
        let current = NSRunningApplication.current
        let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).contains { app in
            guard app.processIdentifier != current.processIdentifier, !app.isTerminated else { return false }
            if let launchedAt = app.launchDate, let currentLaunch = current.launchDate, launchedAt != currentLaunch {
                return launchedAt < currentLaunch
            }
            return app.processIdentifier < current.processIdentifier
        }
        let logger = Logger(subsystem: identifier, category: "Launch")
        guard !existing else {
            logger.notice("Duplicate development launch ignored; an older instance is running.")
            return false
        }

        let lockPath = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(identifier + ".instance.lock").path
        let descriptor = open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            logger.error("Could not open the development instance lock: \(errno).")
            return true
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let failure = errno
            close(descriptor)
            if failure == EWOULDBLOCK {
                logger.notice("Duplicate development launch ignored; the instance lock is held.")
                return false
            }
            logger.error("Could not acquire the development instance lock: \(failure).")
            return true
        }
        developmentInstanceLock = descriptor
        return true
    }
#endif

    @objc private func statusItemActivated(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .leftMouseUp, let subtitle = subtitleStatusView, let window = sender.window {
            let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            if subtitle.bounds.contains(subtitle.convert(windowPoint, from: nil)) {
                subtitle.performClick(nil)
                return
            }
        }
        statusControlView?.handleStatusItemEvent(event)
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
                scrollTimeBudget: appleLyrics.currentLyricRemainingTime, scrollSpeed: subtitles.musicScrollSpeed,
                isInterlude: appleLyrics.isInterlude)
            identity = ["com.apple.Music", title, artist]
        } else if showsCosmos {
            let title = source == "app.podcast.cosmos" ? playback.title : nil
            let artist = source == "app.podcast.cosmos" ? playback.artist : nil
            content = .make(lyric: subtitles.currentText,
                title: title, artist: artist,
                sourceIdentifier: "app.podcast.cosmos", sourceName: String(localized: "小宇宙"),
                scrollStyle: .podcast, scrollSpeed: subtitles.cosmosScrollSpeed)
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
        updateSubtitleItem(resolved, width: (showsApple ? subtitles.musicWidth : subtitles.cosmosWidth).points)
    }

    private func updateSubtitleItem(_ content: MenuBarSubtitleContent?, width: CGFloat) {
        guard content != lastSubtitleContent || width != lastSubtitleWidth else { return }
        lastSubtitleContent = content
        lastSubtitleWidth = width
        guard let content, let button = statusItem?.button else {
            subtitleStatusView?.removeFromSuperview()
            subtitleStatusView = nil
            layoutStatusItem()
            return
        }
        let view: SubtitleStatusView
        if let existing = subtitleStatusView {
            view = existing
        } else {
            view = SubtitleStatusView(frame: NSRect(x: 0, y: 0, width: width, height: button.bounds.height))
            view.target = self
            view.action = #selector(openSubtitleSettings)
            button.addSubview(view)
            subtitleStatusView = view
        }
        layoutStatusItem()
        view.show(content)
    }

    private func layoutStatusItem() {
        guard let item = statusItem, let button = item.button, let controls = statusControlView else { return }
        let subtitleWidth = subtitleStatusView == nil ? 0 : lastSubtitleWidth ?? 0
        let height = button.bounds.height
        let totalWidth = subtitleWidth + statusControlWidth
        if item.length != totalWidth { item.length = totalWidth }
        subtitleStatusView?.setFrameSize(NSSize(width: subtitleWidth, height: height))
        controls.frame = NSRect(x: subtitleWidth, y: 0, width: statusControlWidth, height: height)
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
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
            window.isMovableByWindowBackground = true
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
