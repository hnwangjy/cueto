#if os(macOS)
import AppKit

/// Target Music directly when a browser owns the system Now Playing session.
/// Read only transport state so a slow metadata response cannot delay the icon.
nonisolated enum AppleMusicPlayer {
    static func togglePlayback() -> (playing: Bool?, error: Int?) {
        playbackState(toggling: true)
    }

    static func readPlaybackState() -> (playing: Bool?, error: Int?) {
        playbackState(toggling: false)
    }

    private static func playbackState(toggling: Bool) -> (playing: Bool?, error: Int?) {
        let command = toggling ? """
        set previousState to player state
        playpause
        repeat 8 times
            if player state is not previousState then exit repeat
            delay 0.1
        end repeat
        if player state is previousState then error number -1712
        """ : ""
        let script = """
        with timeout of 2 seconds
            if application id "com.apple.Music" is not running then return "notRunning"
            tell application id "com.apple.Music"
                \(command)
                return player state as text
            end tell
        end timeout
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue
        if let error { return (nil, (error[NSAppleScript.errorNumber] as? Int) ?? -1) }
        guard let result, ["playing", "paused", "stopped"].contains(result) else { return (nil, -600) }
        return (result == "playing", nil)
    }
}
#endif
