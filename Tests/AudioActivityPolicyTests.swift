import Foundation

@main
struct AudioActivityPolicyTests {
    static func main() {
        var policy = AudioActivityPolicy()
        let firefox = "org.mozilla.firefox"
        let music = "com.apple.Music"
        // Silent Firefox IO must not compete with actual Music playback.
        assert(!policy.isPlaybackCandidate(firefox, outputRunning: true))
        assert(policy.isPlaybackCandidate(music, outputRunning: true))
        policy.report(bundleIdentifier: firefox, playing: true)
        assert(policy.isPlaybackCandidate(firefox, outputRunning: true))
        policy.report(bundleIdentifier: firefox, playing: false)
        assert(!policy.isPlaybackCandidate(firefox, outputRunning: true))
        policy.report(bundleIdentifier: music, playing: false)
        assert(!policy.isPlaybackCandidate(music, outputRunning: true))
        policy.report(bundleIdentifier: firefox, playing: true)
        assert(!policy.isPlaybackCandidate(firefox, outputRunning: false))
        policy.retainRunningApplications([music])
        assert(!policy.isPlaybackCandidate(firefox, outputRunning: true))
        assert(!policy.isPlaybackCandidate("com.google.Chrome", outputRunning: true))
        assert(!policy.isPlaybackCandidate("org.mozilla.firefoxdeveloperedition", outputRunning: true))
        print("Audio activity policy tests passed")
    }
}
