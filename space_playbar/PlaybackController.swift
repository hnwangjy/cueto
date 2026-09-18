#if os(macOS)
import AppKit
import Combine
import MediaRemoteAdapter

@MainActor
final class PlaybackController: ObservableObject {
    enum TransportMode {
        case timeSkipping
        case trackNavigation
    }

    @Published private(set) var applicationName = "未在播放"
    @Published private(set) var bundleIdentifier: String?
    @Published private(set) var title: String?
    @Published private(set) var artist: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var hasActiveSession = false
    @Published private(set) var applicationIcon: NSImage?
    @Published private(set) var elapsedTime: TimeInterval?
    @Published private(set) var duration: TimeInterval?

    private let media = MediaController()
    private var progressTimer: AnyCancellable?
    private var referenceElapsedTime: TimeInterval?
    private var referenceDate = Date()
    private var playbackRate = 0.0
    private var pendingPlaybackState: Bool?
    private var pendingStateDeadline = Date.distantPast
    private var pendingStateToken = UUID()

    var transportMode: TransportMode {
        guard let bundleIdentifier = bundleIdentifier?.lowercased() else {
            return .trackNavigation
        }
        return Self.timeSkippingBundleIdentifiers.contains(bundleIdentifier)
            ? .timeSkipping
            : .trackNavigation
    }

    var backwardControlLabel: String {
        transportMode == .timeSkipping ? "后退 15 秒" : "上一首"
    }

    var forwardControlLabel: String {
        transportMode == .timeSkipping ? "前进 30 秒" : "下一首"
    }

    private static let timeSkippingBundleIdentifiers: Set<String> = [
        "app.podcast.cosmos",
        "com.apple.podcasts"
    ]

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
        progressTimer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshDisplayedProgress()
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

    func goBackward() {
        guard hasActiveSession else { return }
        switch transportMode {
        case .timeSkipping:
            seek(by: -15)
        case .trackNavigation:
            media.previousTrack()
            refreshTrackInfoAfterTransportCommand()
        }
    }

    func goForward() {
        guard hasActiveSession else { return }
        switch transportMode {
        case .timeSkipping:
            seek(by: 30)
        case .trackNavigation:
            media.nextTrack()
            refreshTrackInfoAfterTransportCommand()
        }
    }

    private func seek(by offset: TimeInterval) {
        guard let currentTime = currentElapsedTime else { return }
        let upperBound = duration ?? .greatestFiniteMagnitude
        let targetTime = min(max(currentTime + offset, 0), upperBound)

        media.setTime(seconds: targetTime)
        referenceElapsedTime = targetTime
        referenceDate = Date()
        elapsedTime = targetTime

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.media.getTrackInfo { [weak self] info in
                self?.receive(info)
            }
        }
    }

    private func refreshTrackInfoAfterTransportCommand() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.media.getTrackInfo { [weak self] info in
                self?.receive(info)
            }
        }
    }

    private var currentElapsedTime: TimeInterval? {
        guard let referenceElapsedTime else { return nil }
        let advancedTime = isPlaying
            ? Date().timeIntervalSince(referenceDate) * playbackRate
            : 0
        let upperBound = duration ?? .greatestFiniteMagnitude
        return min(max(referenceElapsedTime + advancedTime, 0), upperBound)
    }

    private func refreshDisplayedProgress() {
        elapsedTime = currentElapsedTime
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
            elapsedTime = nil
            duration = nil
            referenceElapsedTime = nil
            playbackRate = 0
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
        duration = payload.durationMicros.map { $0 / 1_000_000 }
        referenceElapsedTime = payload.currentElapsedTime ?? payload.elapsedTimeMicros.map { $0 / 1_000_000 }
        referenceDate = Date()
        playbackRate = reportedPlaying ? (payload.playbackRate ?? 1) : 0
        refreshDisplayedProgress()
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
