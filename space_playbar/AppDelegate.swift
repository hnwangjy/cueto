#if os(macOS)
import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let playback = PlaybackController()
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        _ = updaterController

        let item = NSStatusBar.system.statusItem(
            withLength: Self.statusItemLength(
                for: playback.applicationName,
                hasActiveSession: playback.hasActiveSession,
                sourceCount: playback.activeAudioSourceCount
            )
        )
        let controlView = StatusBarControlView(
            playback: playback,
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

    private static func statusItemLength(
        for applicationName: String,
        hasActiveSession: Bool = true,
        sourceCount: Int = 1
    ) -> CGFloat {
        guard hasActiveSession else { return 30 }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
        ]
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
            let rootView = CuetoSettingsView(model: model)
            let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
            window.title = "Cueto"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 480, height: 360))
            window.minSize = NSSize(width: 440, height: 330)
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
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openCueto()
        return true
    }
}
#endif
