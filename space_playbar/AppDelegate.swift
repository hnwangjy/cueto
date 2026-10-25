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
        notchPanelController = NotchPanelController(playback: playback, subtitles: subtitles) { [weak self] in
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
            onOpenCueto: { [weak self] in self?.openCueto() },
            onQuit: { NSApplication.shared.terminate(nil) }
        )
        controlView.frame = NSRect(
            x: 0,
            y: 0,
            width: item.length,
            height: NSStatusBar.system.thickness
        )
        item.view = controlView

        self.statusControlView = controlView
        self.statusItem = item
        subtitles.$currentText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in self?.updateSubtitleItem(text) }
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

    private func updateSubtitleItem(_ text: String?) {
        guard let text, !text.isEmpty else {
            if let item = subtitleStatusItem { NSStatusBar.system.removeStatusItem(item) }
            subtitleStatusItem = nil
            return
        }
        let item: NSStatusItem
        if let existing = subtitleStatusItem {
            item = existing
        } else {
            item = NSStatusBar.system.statusItem(withLength: 260)
            item.button?.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            item.button?.alignment = .left
            item.button?.cell?.lineBreakMode = .byTruncatingTail
            item.button?.target = self
            item.button?.action = #selector(openSubtitleSettings)
            subtitleStatusItem = item
        }
        item.button?.title = text
        item.button?.toolTip = text + "\n点击打开 Cueto 设置"
        item.button?.setAccessibilityLabel("小宇宙字幕：\(text)")
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
            let rootView = CuetoSettingsView(model: model, excludedApps: excludedApps, subtitles: subtitles)
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
