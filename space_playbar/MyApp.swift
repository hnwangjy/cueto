import SwiftUI

#if os(macOS)
import AppKit
#endif

@main
struct MyApp: App {
#if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
#endif

    var body: some Scene {
#if os(macOS)
        Settings {
            EmptyView()
        }
#else
        WindowGroup {
            ContentView()
        }
#endif
    }
}
