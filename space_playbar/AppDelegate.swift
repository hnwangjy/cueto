#if os(macOS)
import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let playback = PlaybackController()
    private var statusItem: NSStatusItem?
    private var hostingView: NSHostingView<StatusBarControlsView>?
    private var sourceNameObservation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: Self.statusItemLength(for: playback.applicationName))
        guard let button = item.button else { return }

        button.image = nil
        button.title = ""
        button.action = nil
        button.toolTip = "Cueto"

        let rootView = StatusBarControlsView(
            playback: playback,
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
        return min(max(154 + nameWidth, 188), 244)
    }
}
#endif
