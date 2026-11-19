#if os(macOS)
import AppKit

struct MusicSnapshot: Sendable {
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let position: Double
    let playing: Bool
    let identifier: String
    let sampledAt: TimeInterval

    nonisolated var key: String { "\(identifier)|\(title)|\(artist)|\(album)|\(Int(duration.rounded()))" }
}

/// Target Music directly when a browser owns the system Now Playing session.
/// Transport and metadata are read independently so artwork cannot delay a command.
nonisolated enum AppleMusicPlayer {
    static func togglePlayback() -> (playing: Bool?, error: Int?) {
        playbackState(toggling: true)
    }

    static func readPlaybackState() -> (playing: Bool?, error: Int?) {
        playbackState(toggling: false)
    }

    static func readTracks(includeUpcoming: Bool) -> (MusicSnapshot?, MusicSnapshot?, Int?) {
        let script = """
        with timeout of 2 seconds
        if application id "com.apple.Music" is not running then return {}
        tell application id "com.apple.Music"
            if player state is stopped then return {}
            set t to current track
            set upcoming to {}
            if \(includeUpcoming ? "true" : "false") then
                try
                    if shuffle enabled is false and fixed indexing is false then
                        set p to current playlist
                        set i to index of t
                        if persistent ID of track i of p is persistent ID of t then
                            if i < count tracks of p then
                                set n to track (i + 1) of p
                                set upcoming to {name of n, artist of n, album of n, duration of n, 0, "paused", persistent ID of n}
                            end if
                        end if
                    end if
                end try
            end if
            return {{name of t, artist of t, album of t, duration of t, player position, player state as text, persistent ID of t}, upcoming}
        end tell
        end timeout
        """
        var error: NSDictionary?
        guard let program = NSAppleScript(source: script) else { return (nil, nil, -1) }
        let result = program.executeAndReturnError(&error)
        if let error { return (nil, nil, (error[NSAppleScript.errorNumber] as? Int) ?? -1) }
        return (result.atIndex(1).flatMap(Self.decodeTrack), result.atIndex(2).flatMap(Self.decodeTrack), nil)
    }

    nonisolated private static func decodeTrack(_ result: NSAppleEventDescriptor) -> MusicSnapshot? {
        guard result.numberOfItems == 7,
              let title = result.atIndex(1)?.stringValue, !title.isEmpty,
              let artist = result.atIndex(2)?.stringValue, !artist.isEmpty,
              let album = result.atIndex(3)?.stringValue,
              let duration = result.atIndex(4)?.doubleValue, duration.isFinite, duration > 0,
              let position = result.atIndex(5)?.doubleValue, position.isFinite else { return nil }
        return (MusicSnapshot(title: title, artist: artist, album: album, duration: duration,
                              position: max(0, position), playing: result.atIndex(6)?.stringValue == "playing",
                              identifier: result.atIndex(7)?.stringValue ?? title,
                              sampledAt: ProcessInfo.processInfo.systemUptime))
    }

    static func readArtwork(for identifier: String) -> Data? {
        // Persistent IDs are hexadecimal, never interpolated track titles.
        guard identifier.range(of: "^[0-9A-Fa-f]{16}$", options: .regularExpression) != nil else { return nil }
        let script = """
        with timeout of 2 seconds
            if application id "com.apple.Music" is not running then return missing value
            tell application id "com.apple.Music"
                set t to current track
                if persistent ID of t is not "\(identifier)" then return missing value
                return data of artwork 1 of t
            end tell
        end timeout
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
        guard error == nil, let data = result?.data, !data.isEmpty else { return nil }
        return data
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
