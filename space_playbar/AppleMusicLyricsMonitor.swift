#if os(macOS)
#if CUETO_APPLE_MUSIC_LYRICS
import AppKit
import Combine
import CryptoKit
import Network
import OSLog

private struct MusicSnapshot: Sendable {
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

private struct LRCLIBResponse: Codable, Sendable {
    let syncedLyrics: String?
    let instrumental: Bool?
}

@MainActor
final class AppleMusicLyricsMonitor: ObservableObject {
    private let directProbe = AppleMusicDirectProbe()
    @Published private(set) var usesDirectLyrics = UserDefaults.standard.bool(forKey: "appleMusicDirectLyrics")

    func openDirectProbe() {
        usesDirectLyrics = true
        UserDefaults.standard.set(true, forKey: "appleMusicDirectLyrics")
        generation = UUID()
        request?.cancel()
        loading = false
        recovery.reset()
        prefetchRequest?.cancel()
        prefetched = nil
        statusMessage = "请连接 Apple Music 并读取当前歌曲。"
        configureDirectConnection()
        directProbe.open()
        if directProbe.isConnected, let snapshot { loadLyrics(for: snapshot) }
    }

    private func configureDirectConnection() {
        directProbe.currentTrack = { [weak self] in
            guard let song = self?.snapshot else { return nil }
            return AppleMusicProbeTrack(key: song.key, title: song.title, artist: song.artist,
                                       album: song.album, duration: song.duration)
        }
        directProbe.onLyrics = { [weak self] key, cues in
            guard let self, self.isEnabled, self.snapshot?.key == key else { return }
            self.generation = UUID()
            self.usesDirectLyrics = true
            self.request?.cancel()
            self.prefetchRequest?.cancel()
            self.prefetchKey = nil
            self.prefetched = nil
            self.loading = false
            self.recovery.reset()
            self.cues = cues
            self.statusMessage = ""
            self.updateLine()
        }
        directProbe.onSessionConnected = { [weak self] in
            guard let self, self.isEnabled, self.usesDirectLyrics else { return }
            // Let the existing request finish if it is already restoring this session.
            if !self.loading { self.retry() }
        }
        directProbe.onSessionDisconnected = { [weak self] in
            guard let self else { return }
            self.generation = UUID()
            self.request?.cancel()
            self.loading = false
            self.recovery.reset()
            self.cues = []
            self.currentText = nil
            self.statusMessage = "Apple Music 已断开，请重新连接。"
        }
    }
    @Published var isEnabled = UserDefaults.standard.bool(forKey: "showAppleMusicLyrics") {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "showAppleMusicLyrics")
            generation = UUID()
            request?.cancel()
            request = nil
            resetRecoveryAndPrefetch()
            snapshot = nil
            cues = []
            currentText = nil
            needsPermission = false
            isPlaying = false
            configure()
        }
    }
    @Published private(set) var currentText: String?
    @Published private(set) var statusMessage = ""
    @Published private(set) var needsPermission = false
    @Published private(set) var isPlaying = false
    private var samplingTimer: AnyCancellable?
    private var displayTimer: AnyCancellable?
    private let reader = DispatchQueue(label: "com.wangjiayuan.cueto.apple-music", qos: .utility)
    private var reading = false
    private var generation = UUID()
    private var snapshot: MusicSnapshot?
    private var cues: [LyricCue] = []
    private var request: Task<Void, Never>?
    private var loading = false
    private var recovery = LyricsRecoverySchedule()
    private let networkMonitor = NWPathMonitor()
    private var wakeObservation: AnyCancellable?
    private var prefetchRequest: Task<Void, Never>?
    private var prefetchKey: String?
    private var prefetched: (String, LRCLIBResponse)?
    private var nextQueueRead = Date.distantPast
    private let logger = Logger(subsystem: "com.wangjiayuan.cueto", category: "LyricsRecovery")

    init() {
        configureDirectConnection()
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in self?.resumeAfterConnectionChange() }
        }
        networkMonitor.start(queue: DispatchQueue(label: "com.wangjiayuan.cueto.lyrics-network"))
        wakeObservation = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resumeAfterConnectionChange() }
        configure()
    }

    deinit { networkMonitor.cancel() }

    private func resetRecoveryAndPrefetch() {
        loading = false
        recovery.reset()
        prefetchRequest?.cancel()
        prefetchRequest = nil
        prefetchKey = nil
        prefetched = nil
        nextQueueRead = .distantPast
    }

    private func resumeAfterConnectionChange() {
        guard isEnabled else { return }
        recovery.connectionRecovered(at: Date())
        poll()
    }

    func retry() {
        generation = UUID()
        request?.cancel()
        request = nil
        resetRecoveryAndPrefetch()
        snapshot = nil
        cues = []
        currentText = nil
        isPlaying = false
        needsPermission = false
        poll()
    }

    private func configure() {
        samplingTimer = nil
        displayTimer = nil
        guard isEnabled else { statusMessage = ""; return }
        samplingTimer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.poll() }
        displayTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.updateLine() }
        poll()
    }

    private func poll() {
        guard isEnabled, !reading, !needsPermission else { return }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").contains(where: { !$0.isTerminated }) else {
            if snapshot != nil { generation = UUID(); request?.cancel(); snapshot = nil; cues = []; resetRecoveryAndPrefetch() }
            currentText = nil
            isPlaying = false
            statusMessage = "请在 Apple Music 中播放歌曲"
            return
        }
        reading = true
        let token = generation
        let readQueue = Date() >= nextQueueRead
        if readQueue { nextQueueRead = Date().addingTimeInterval(15) }
        reader.async { [weak self] in
            let (state, upcoming, error) = Self.readMusic(includeUpcoming: readQueue)
            DispatchQueue.main.async {
                guard let self else { return }
                self.reading = false
                guard self.isEnabled, self.generation == token else { return }
                if let error {
                    self.currentText = nil
                    self.isPlaying = false
                    self.snapshot = nil
                    self.cues = []
                    self.generation = UUID()
                    self.request?.cancel()
                    self.resetRecoveryAndPrefetch()
                    self.needsPermission = error == -1743
                    self.statusMessage = self.needsPermission ? "需要允许 Cueto 读取 Apple Music" : "暂时无法读取 Apple Music，请重试"
                    return
                }
                guard let state else {
                    self.isPlaying = false
                    self.generation = UUID()
                    self.request?.cancel()
                    self.resetRecoveryAndPrefetch()
                    self.snapshot = nil
                    self.cues = []
                    self.currentText = nil
                    self.statusMessage = "请在 Apple Music 中播放歌曲"
                    return
                }
                let changed = self.snapshot?.key != state.key
                self.snapshot = state
                self.isPlaying = state.playing
                if changed {
                    self.generation = UUID()
                    self.recovery.reset()
                    self.cues = []
                    self.currentText = nil
                    self.loadLyrics(for: state)
                } else if !self.loading, state.playing, self.recovery.isDue(at: Date()) {
                    self.logger.info("Retrying current lyrics after cooldown or connection recovery")
                    self.loadLyrics(for: state)
                }
                if readQueue { self.prepareUpcoming(upcoming) }
                self.updateLine()
            }
        }
    }

    private func updateLine() {
        guard isEnabled, let snapshot else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - snapshot.sampledAt
        // Do not keep advancing indefinitely if Music stops answering.
        let position = snapshot.position + (snapshot.playing ? min(max(elapsed, 0), 1.2) : 0)
        let text = LRCLyrics.line(at: min(position, snapshot.duration), in: cues)
        if currentText != text { currentText = text }
    }

    private func loadLyrics(for song: MusicSnapshot) {
        request?.cancel()
        loading = true
        let token = generation
        statusMessage = "正在匹配歌词…"
        if !usesDirectLyrics, let prepared = prefetched, prepared.0 == song.key {
            apply(prepared.1)
            prefetched = nil
            loading = false
            logger.info("Consumed prepared lyrics for the verified current track")
            return
        }
        request = Task { [weak self] in
          defer { if let self, self.generation == token { self.loading = false } }
          for attempt in 0..<3 {
            do {
                if let self, self.usesDirectLyrics {
                    let track = AppleMusicProbeTrack(key: song.key, title: song.title, artist: song.artist,
                                                    album: song.album, duration: song.duration)
                    let directCues = try await self.directProbe.fetchLyrics(for: track)
                    guard !Task.isCancelled, self.generation == token else { return }
                    self.cues = directCues
                    self.logger.info("Apple Music direct lyrics ready: \(directCues.filter { !$0.text.isEmpty }.count) lines")
                    self.recovery.reset()
                    self.statusMessage = ""
                    self.updateLine()
                    return
                }
                let result = try await Self.fetchLyrics(song)
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.apply(result)
                return
            } catch {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                let reason = (error as? AppleMusicDirectError)?.localizedDescription ?? LyricsHTTPClient.failureMessage(error)
                guard attempt < 2 else {
                    self.recovery.failed(at: Date())
                    self.statusMessage = reason + "，稍后自动重试"
                    return
                }
                self.statusMessage = reason + "，正在重试…"
                do { try await Task.sleep(for: .seconds(attempt == 0 ? 2 : 6)) }
                catch { return }
                guard !Task.isCancelled, self.generation == token else { return }
            }
          }
        }
    }

    private func apply(_ result: LRCLIBResponse) {
        cues = LRCLyrics.parse(result.syncedLyrics ?? "")
        statusMessage = result.instrumental == true ? "纯音乐" : (cues.isEmpty ? "没有找到同步歌词" : "")
        if cues.isEmpty, result.instrumental != true { recovery.failed(at: Date(), missing: true) }
        else { recovery.reset() }
        updateLine()
    }

    private func prepareUpcoming(_ song: MusicSnapshot?) {
        guard !usesDirectLyrics else { return }
        guard let song, song.key != snapshot?.key else {
            prefetchRequest?.cancel(); prefetchRequest = nil
            prefetchKey = nil; prefetched = nil
            return
        }
        guard song.key != prefetchKey else { return }
        prefetchRequest?.cancel()
        prefetchKey = song.key
        prefetched = nil
        prefetchRequest = Task { [weak self] in
            do {
                // Foreground lyrics always have priority over speculative work.
                while self?.loading == true {
                    try await Task.sleep(for: .seconds(1))
                }
                try Task.checkCancellation()
                let result = try await Self.fetchLyrics(song)
                guard !Task.isCancelled, let self, self.isEnabled, self.prefetchKey == song.key else { return }
                if result.instrumental == true || !LRCLyrics.parse(result.syncedLyrics ?? "").isEmpty {
                    self.prefetched = (song.key, result)
                    self.logger.info("Prepared one upcoming playlist candidate")
                }
            } catch {
                // No retries or user-facing errors for an unconfirmed next track.
            }
        }
    }

    nonisolated private static func fetchLyrics(_ song: MusicSnapshot) async throws -> LRCLIBResponse {
        let hash = SHA256.hash(data: Data(song.key.utf8)).map { String(format: "%02x", $0) }.joined()
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Cueto")
            .appendingPathComponent("Lyrics")
        let file = directory.appendingPathComponent(hash + ".json")
        if let data = try? Data(contentsOf: file),
           let result = try? JSONDecoder().decode(LRCLIBResponse.self, from: data) {
            return result
        }
        var url = URLComponents(string: "https://lrclib.net/api/get")!
        url.queryItems = [URLQueryItem(name: "track_name", value: song.title),
                         URLQueryItem(name: "artist_name", value: song.artist),
                         URLQueryItem(name: "album_name", value: song.album),
                         URLQueryItem(name: "duration", value: String(Int(song.duration.rounded())))]
        var exact: LRCLIBResponse?
        var exactFailure: Error?
        do {
            let (data, status) = try await LyricsHTTPClient.data(from: url.url!, allowing: [200, 404])
            if status == 200 { exact = try JSONDecoder().decode(LRCLIBResponse.self, from: data) }
        } catch {
            try Task.checkCancellation()
            exactFailure = error
        }
        if exact == nil || (exact?.instrumental != true && LRCLyrics.parse(exact?.syncedLyrics ?? "").isEmpty) {
            var search = URLComponents(string: "https://lrclib.net/api/search")!
            search.queryItems = [URLQueryItem(name: "track_name", value: song.title)]
            let (searchData, _) = try await LyricsHTTPClient.data(from: search.url!)
            let candidates = try JSONDecoder().decode([LyricMatchCandidate].self, from: searchData)
            guard let match = LyricMatching.select(title: song.title, artist: song.artist, albumName: song.album,
                                                   duration: song.duration, from: candidates) else {
                if let exactFailure { throw exactFailure }
                return LRCLIBResponse(syncedLyrics: nil, instrumental: nil)
            }
            let result = LRCLIBResponse(syncedLyrics: match.syncedLyrics, instrumental: match.instrumental)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let encoded = try? JSONEncoder().encode(result) { try? encoded.write(to: file, options: .atomic) }
            return result
        }
        let result = exact ?? LRCLIBResponse(syncedLyrics: nil, instrumental: nil)
        // Persist successful synced lyrics only; missing tracks can be retried later.
        if result.instrumental == true || !LRCLyrics.parse(result.syncedLyrics ?? "").isEmpty {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let encoded = try? JSONEncoder().encode(result) { try? encoded.write(to: file, options: .atomic) }
        }
        return result
    }

    nonisolated private static func readMusic(includeUpcoming: Bool) -> (MusicSnapshot?, MusicSnapshot?, Int?) {
        let script = """
        with timeout of 2 seconds
        tell application id "com.apple.Music"
            if not running then return {}
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
}
#else
import Combine

/// Release builds keep the experimental Apple Music integration dormant,
/// regardless of preferences saved by an earlier development build.
@MainActor
final class AppleMusicLyricsMonitor: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var currentText: String? = nil
    @Published private(set) var isPlaying = false
}
#endif
#endif
