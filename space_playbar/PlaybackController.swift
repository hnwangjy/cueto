#if os(macOS)
import AppKit
import Combine
import MediaRemoteAdapter

@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var applicationName = "未在播放"
    @Published private(set) var bundleIdentifier: String?
    @Published private(set) var title: String?
    @Published private(set) var artist: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var hasActiveSession = false
    @Published private(set) var applicationIcon: NSImage?

    private let media = MediaController()
    private var pendingPlaybackState: Bool?
    private var pendingStateDeadline = Date.distantPast
    private var pendingStateToken = UUID()

    init() {
        media.onTrackInfoReceived = { [weak self] info in
            self?.receive(info)
        }
        media.onListenerTerminated = { [weak self] in
            self?.restartListener()
        }
        media.startListening()
        media.getTrackInfo { [weak self] info in
            self?.receive(info)
        }
    }

    func playPause() {
        guard hasActiveSession else { return }

        let targetState = !isPlaying
        pendingPlaybackState = targetState
        pendingStateDeadline = Date().addingTimeInterval(1.2)
        pendingStateToken = UUID()
        let token = pendingStateToken
        isPlaying = targetState

        if targetState {
            media.play()
        } else {
            media.pause()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.pendingStateToken == token else { return }
            self.pendingPlaybackState = nil
            self.media.getTrackInfo { [weak self] info in
                self?.receive(info)
            }
        }
    }

    func skipBackward() {
        guard hasActiveSession else { return }
        media.goBackFifteenSeconds()
    }

    func skipForward() {
        guard hasActiveSession else { return }
        media.skipFifteenSeconds()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.media.skipFifteenSeconds()
        }
    }

    private func receive(_ info: TrackInfo?) {
        guard let payload = info?.payload else {
            if pendingPlaybackState != nil, Date() < pendingStateDeadline {
                return
            }
            applicationName = "未在播放"
            bundleIdentifier = nil
            title = nil
            artist = nil
            isPlaying = false
            hasActiveSession = false
            applicationIcon = nil
            return
        }

        applicationName = payload.applicationName?.nonEmpty ?? sourceName(for: payload.bundleIdentifier)
        bundleIdentifier = payload.bundleIdentifier
        title = payload.title?.nonEmpty
        artist = payload.artist?.nonEmpty
        let reportedPlaying = payload.isPlaying ?? ((payload.playbackRate ?? 0) > 0)
        if let pendingPlaybackState {
            if reportedPlaying == pendingPlaybackState || Date() >= pendingStateDeadline {
                self.pendingPlaybackState = nil
                isPlaying = reportedPlaying
            }
        } else {
            isPlaying = reportedPlaying
        }
        hasActiveSession = true
        applicationIcon = icon(for: payload.bundleIdentifier)
    }

    private func sourceName(for bundleIdentifier: String?) -> String {
        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return "正在播放"
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    private func icon(for bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    private func restartListener() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.media.startListening()
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
#endif
