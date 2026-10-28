import Foundation

/// Output IO can remain active while a browser renders silence. A media pause
/// must also take precedence over IO activity for every application.
struct AudioActivityPolicy {
    private var reportedStates: [String: Bool] = [:]

    mutating func report(bundleIdentifier: String, playing: Bool) {
        reportedStates[bundleIdentifier] = playing
    }

    mutating func retainRunningApplications(_ identifiers: Set<String>) {
        reportedStates = reportedStates.filter { identifiers.contains($0.key) }
    }

    func isPlaybackCandidate(_ identifier: String, outputRunning: Bool) -> Bool {
        guard outputRunning else { return false }
        if let state = reportedStates[identifier] { return state }
        return !Self.requiresPlaybackConfirmation(identifier)
    }

    static func requiresPlaybackConfirmation(_ identifier: String) -> Bool {
        let identifier = identifier.lowercased()
        return ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly", "org.mozilla.librewolf",
                "com.apple.safari", "com.google.chrome", "org.chromium.chromium",
                "com.microsoft.edgemac", "com.brave.browser", "company.thebrowser.browser",
                "com.operasoftware.opera", "com.vivaldi.vivaldi", "app.zen-browser.zen"]
            .contains { identifier == $0 || identifier.hasPrefix($0 + ".") }
    }
}
