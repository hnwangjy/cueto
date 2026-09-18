#if os(macOS)
import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let playback = PlaybackController()
    private var statusItem: NSStatusItem?
    private var hostingView: NSHostingView<StatusBarControlsView>?
    private var sourceNameObservation: AnyCancellable?
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

        let item = NSStatusBar.system.statusItem(withLength: Self.statusItemLength(for: playback.applicationName))
        guard let button = item.button else { return }

        button.image = nil
        button.title = ""
        button.action = nil
        button.toolTip = "Cueto"

        let rootView = StatusBarControlsView(
            playback: playback,
            onOpenCueto: { [weak self] in self?.openCueto() },
            onQuit: { NSApplication.shared.terminate(nil) }
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: button.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])

        self.hostingView = hostingView
        self.statusItem = item
        sourceNameObservation = playback.$applicationName
            .removeDuplicates()
            .sink { [weak item] name in
                item?.length = Self.statusItemLength(for: name)
            }
    }

    private static func statusItemLength(for applicationName: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
        ]
        let nameWidth = ceil((applicationName as NSString).size(withAttributes: attributes).width)
        return min(max(136 + nameWidth, 174), 228)
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
