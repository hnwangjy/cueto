#if os(macOS)
import AppKit
import Combine
import MediaRemoteAdapter
import OSLog

@MainActor
final class PlaybackController: ObservableObject {
    static let cosmosResumeRecoveryPreference = "recoverCosmosAudioOnResume"

    enum TransportMode {
        case timeSkipping
        case trackNavigation
    }

    @Published private(set) var applicationName = String(localized: "未在播放")
    @Published private(set) var bundleIdentifier: String?
    @Published private(set) var title: String?
    @Published private(set) var artist: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var hasActiveSession = false
    @Published private(set) var applicationIcon: NSImage?
    @Published private(set) var artwork: NSImage? {
        didSet {
            if artwork !== oldValue {
                artworkPalette = artwork.flatMap(ArtworkProgressPalette.extract)
            }
        }
    }
    @Published private(set) var artworkPalette: ArtworkProgressPalette?
    private var artworkData: String?
    @Published private(set) var elapsedTime: TimeInterval?
    @Published private(set) var seekError: String?
    private var seekToken = UUID()
    private var seekInFlight = false
    private var seekSettlingUntil = Date.distantPast
    private var lastSeekSampledAt = 0.0
    var progressIdentity: String { "\(bundleIdentifier ?? "")|\(title ?? "")|\(artist ?? "")|\(duration ?? 0)" }
    @Published private(set) var duration: TimeInterval?
    @Published private(set) var activeAudioSources: [ActiveAudioSource] = []
    @Published private(set) var availableAudioSources: [ActiveAudioSource] = []
    @Published private(set) var openingSourceIdentifier: String?
    @Published private(set) var sourceOpenError: String?

    func openApplication(for source: ActiveAudioSource) {
        guard openingSourceIdentifier == nil,
              !excludedApps.bundleIdentifiers.contains(source.bundleIdentifier) else { return }
        sourceOpenError = nil
        let runningApp = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == source.bundleIdentifier
        }
        guard let url = runningApp?.bundleURL
                ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier) else {
            sourceOpenError = String(localized: "找不到 \(source.applicationName)，应用可能已被移除。")
            return
        }
        openingSourceIdentifier = source.bundleIdentifier
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] app, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.openingSourceIdentifier = nil
                if let error {
                    self.sourceOpenError = String(localized: "无法打开 \(source.applicationName)：\(error.localizedDescription)")
                } else {
                    app?.unhide()
                    app?.activate(options: [.activateAllWindows])
                }
            }
        }
    }

    private let media = MediaController()
    private let audioSourceMonitor = ActiveAudioSourceMonitor()
    let excludedApps: ExcludedAudioApps
    private var progressTimer: AnyCancellable?
    private var audioSourceObservation: AnyCancellable?
    private var processSourceObservation: AnyCancellable?
    private var detectedAudioSources: [ActiveAudioSource] = []
    private var detectedProcessSources: [ActiveAudioSource] = []
    private var audioActivityPolicy = AudioActivityPolicy()
    private var playbackCandidates: [ActiveAudioSource] {
        detectedAudioSources.filter {
            audioActivityPolicy.isPlaybackCandidate($0.bundleIdentifier, outputRunning: $0.isRunningOutput)
        }
    }
    private var referenceElapsedTime: TimeInterval?
    private var referenceDate = Date()
    private var playbackRate = 0.0
    private let transportLogger = Logger(subsystem: "com.wangjiayuan.cueto", category: "PlaybackTransport")
    private let musicQueue = DispatchQueue(label: "com.wangjiayuan.cueto.music-transport", qos: .userInitiated)
    private let musicMetadataQueue = DispatchQueue(label: "com.wangjiayuan.cueto.music-metadata", qos: .utility)
    private var needsMusicMetadata = false
    private var musicMetadataInFlight = false
    private var musicMetadataGeneration = UUID()
    private var nextMusicMetadataRead = Date.distantPast
    private var musicArtworkKey: String?
    private var nextMusicArtworkRead = Date.distantPast
    private var confirmedMusicPlaying: Bool?
    private var musicStateSampledAt = 0.0
    private var musicReadInFlight = false
    private var nextMusicRead = Date.distantPast
    private var pendingPlaybackState: Bool?
    private var pendingStateDeadline = Date.distantPast
    private var pendingStateToken = UUID()
    private var cosmosPlaybackRequest: UUID?
    @Published private(set) var cosmosPendingPlayback: Bool?

    var transportMode: TransportMode {
        guard let bundleIdentifier = bundleIdentifier?.lowercased() else {
            return .trackNavigation
        }
        return Self.timeSkippingBundleIdentifiers.contains(bundleIdentifier)
            ? .timeSkipping
            : .trackNavigation
    }

    var backwardControlSymbol: String {
        bundleIdentifier == "app.podcast.cosmos" ? "15.arrow.trianglehead.counterclockwise" : "backward.end"
    }

    var forwardControlSymbol: String {
        bundleIdentifier == "app.podcast.cosmos" ? "30.arrow.trianglehead.clockwise" : "forward.end"
    }

    var backwardControlLabel: String {
        transportMode == .timeSkipping ? String(localized: "后退 15 秒") : String(localized: "上一首")
    }

    var forwardControlLabel: String {
        transportMode == .timeSkipping ? String(localized: "前进 30 秒") : String(localized: "下一首")
    }

    private static let timeSkippingBundleIdentifiers: Set<String> = [
        "app.podcast.cosmos",
        "com.apple.podcasts"
    ]

    init(excludedApps: ExcludedAudioApps) {
        self.excludedApps = excludedApps
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
        audioSourceObservation = audioSourceMonitor.$sources
            .sink { [weak self] sources in
                self?.detectedAudioSources = sources
                self?.audioActivityPolicy.retainRunningApplications(Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)))
                self?.reconcileDisplayedSourceWithRunningAudio()
            }
        processSourceObservation = audioSourceMonitor.$processSources
            .sink { [weak self] sources in
                self?.detectedProcessSources = sources
                self?.refreshAvailableAudioSources()
            }
        excludedApps.$bundleIdentifiers
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.reconcileDisplayedSourceWithRunningAudio()
                self.refreshAvailableAudioSources()
                self.media.getTrackInfo { [weak self] info in self?.receive(info) }
            }
            .store(in: &exclusionObservations)
        progressTimer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshDisplayedProgress()
            }
    }

    private var exclusionObservations = Set<AnyCancellable>()

    var activeAudioSourceCount: Int {
        activeAudioSources.count
    }

    func playPause() {
        guard hasActiveSession else { return }
        if bundleIdentifier == "com.apple.Music" {
            toggleMusicPlayback()
            return
        }
        if bundleIdentifier == "app.podcast.cosmos" {
            toggleCosmosPlayback()
            return
        }

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

    private func toggleCosmosPlayback() {
        guard cosmosPlaybackRequest == nil else { return }
        let request = UUID()
        cosmosPlaybackRequest = request
        let targetState = !isPlaying
        cosmosPendingPlayback = targetState
        pendingPlaybackState = nil
        pendingStateToken = UUID()

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard self?.cosmosPlaybackRequest == request else { return }
            self?.finishCosmosPlaybackRequest()
        }
        media.getTrackInfo { [weak self] info in
            guard let self, self.cosmosPlaybackRequest == request else { return }
            guard self.bundleIdentifier == "app.podcast.cosmos",
                  let payload = info?.payload, payload.bundleIdentifier == "app.podcast.cosmos" else {
                self.finishCosmosPlaybackRequest()
                return
            }
            let playing = payload.isPlaying ?? ((payload.playbackRate ?? 0) > 0)
            self.receive(info)
            guard playing != targetState, self.bundleIdentifier == "app.podcast.cosmos" else {
                self.finishCosmosPlaybackRequest()
                return
            }
            // Reposition while silent so an already audible stream is never rewound.
            if targetState, UserDefaults.standard.bool(forKey: Self.cosmosResumeRecoveryPreference),
               let position = payload.elapsedTimeMicros.map({ $0 / 1_000_000 }) ?? payload.currentElapsedTime,
               position.isFinite {
                let seekToken = self.seekToken
                self.media.setTime(seconds: max(0, position))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                    guard let self, self.cosmosPlaybackRequest == request else { return }
                    // Re-read the session after the seek instead of relying on its prior state.
                    self.media.getTrackInfo { [weak self] prepared in
                        guard let self, self.cosmosPlaybackRequest == request else { return }
                        guard self.bundleIdentifier == "app.podcast.cosmos",
                              let current = prepared?.payload,
                              current.bundleIdentifier == "app.podcast.cosmos",
                              current.PID == payload.PID, current.uniqueIdentifier == payload.uniqueIdentifier,
                              self.seekToken == seekToken else {
                            self.finishCosmosPlaybackRequest()
                            return
                        }
                        self.receive(prepared)
                        guard self.cosmosPlaybackRequest == request,
                              self.bundleIdentifier == "app.podcast.cosmos" else { return }
                        self.sendCosmosPlaybackCommand(playing: true, request: request)
                    }
                }
            } else {
                self.sendCosmosPlaybackCommand(playing: targetState, request: request)
            }
        }
    }

    private func finishCosmosPlaybackRequest() {
        cosmosPlaybackRequest = nil
        cosmosPendingPlayback = nil
    }

    private func sendCosmosPlaybackCommand(playing: Bool, request: UUID) {
        if playing {
            // Cosmos can ignore explicit Play while paused. Its toggle handles resume.
            media.togglePlayPause()
        } else {
            media.pause()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
            guard let self, self.cosmosPlaybackRequest == request else { return }
            self.media.getTrackInfo { [weak self] confirmed in
                guard let self, self.cosmosPlaybackRequest == request else { return }
                self.finishCosmosPlaybackRequest()
                guard self.bundleIdentifier == "app.podcast.cosmos",
                      confirmed?.payload.bundleIdentifier == "app.podcast.cosmos" else { return }
                self.receive(confirmed)
            }
        }
    }

    private func toggleMusicPlayback() {
        sourceOpenError = nil
        // Keep the confirmed icon until Music replies. The global media target
        // may be an entirely different app, so it cannot acknowledge this command.
        musicQueue.async { [weak self] in
            let result = AppleMusicPlayer.togglePlayback()
            DispatchQueue.main.async {
                guard let self, self.bundleIdentifier == "com.apple.Music" else { return }
                self.transportLogger.info("Music toggle error=\(result.error ?? 0)")
                if let playing = result.playing {
                    self.applyMusicState(playing)
                } else {
                    self.sourceOpenError = result.error == -1743
                        ? String(localized: "需要允许 Cueto 控制音乐，请在系统设置的自动化中授权。")
                        : String(localized: "未能控制音乐，请重试。")
                }
                self.media.getTrackInfo { [weak self] info in self?.receive(info) }
            }
        }
    }

    private func refreshMusicState() {
        guard confirmedMusicPlaying != nil, bundleIdentifier == "com.apple.Music",
              !musicReadInFlight, Date() >= nextMusicRead else { return }
        musicReadInFlight = true
        nextMusicRead = Date().addingTimeInterval(1)
        musicQueue.async { [weak self] in
            let result = AppleMusicPlayer.readPlaybackState()
            DispatchQueue.main.async {
                guard let self else { return }
                self.musicReadInFlight = false
                guard self.bundleIdentifier == "com.apple.Music" else { return }
                if let playing = result.playing { self.applyMusicState(playing) }
                else { self.confirmedMusicPlaying = nil }
            }
        }
    }

    private func refreshMusicMetadata() {
        guard needsMusicMetadata, bundleIdentifier == "com.apple.Music", !musicMetadataInFlight,
              Date() >= nextMusicMetadataRead else { return }
        musicMetadataInFlight = true
        nextMusicMetadataRead = Date().addingTimeInterval(2)
        let generation = musicMetadataGeneration
        let artworkKey = musicArtworkKey
        let canRetryArtwork = artwork == nil && Date() >= nextMusicArtworkRead
        musicMetadataQueue.async { [weak self] in
            let (snapshot, _, _) = AppleMusicPlayer.readTracks(includeUpcoming: false)
            let readsArtwork = snapshot.map { $0.key != artworkKey || canRetryArtwork } ?? false
            let data = readsArtwork ? snapshot.flatMap { AppleMusicPlayer.readArtwork(for: $0.identifier) } : nil
            // Confirm the track after a potentially slower artwork request.
            let refreshed = readsArtwork ? AppleMusicPlayer.readTracks(includeUpcoming: false).0 : snapshot
            let state = refreshed?.key == snapshot?.key ? refreshed : nil
            DispatchQueue.main.async {
                guard let self else { return }
                self.musicMetadataInFlight = false
                guard self.bundleIdentifier == "com.apple.Music", self.needsMusicMetadata,
                      self.musicMetadataGeneration == generation, let state else { return }
                if self.musicArtworkKey != state.key { self.clearArtwork() }
                self.title = state.title
                self.artist = state.artist.nonEmpty
                self.duration = state.duration
                if !self.seekInFlight, state.sampledAt >= max(self.musicStateSampledAt, self.lastSeekSampledAt) {
                    self.referenceElapsedTime = state.position + (state.playing ? max(0, ProcessInfo.processInfo.systemUptime - state.sampledAt) : 0)
                    self.referenceDate = Date()
                    self.applyMusicState(state.playing)
                }
                if readsArtwork {
                    self.artwork = data.flatMap(NSImage.init(data:))
                    self.musicArtworkKey = state.key
                    self.nextMusicArtworkRead = Date().addingTimeInterval(10)
                }
            }
        }
    }

    private var hasRecentMusicState: Bool {
        bundleIdentifier == "com.apple.Music" && confirmedMusicPlaying != nil &&
            ProcessInfo.processInfo.systemUptime - musicStateSampledAt < 2.5
    }

    private func applyMusicState(_ playing: Bool) {
        confirmedMusicPlaying = playing
        musicStateSampledAt = ProcessInfo.processInfo.systemUptime
        pendingPlaybackState = nil
        audioActivityPolicy.report(bundleIdentifier: "com.apple.Music", playing: playing)
        referenceElapsedTime = currentElapsedTime
        referenceDate = Date()
        isPlaying = playing
        playbackRate = playing ? 1 : 0
        refreshActiveAudioSources()
        refreshAvailableAudioSources()
        elapsedTime = currentElapsedTime
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
        seek(to: currentTime + offset)
    }

    func seek(to seconds: TimeInterval) {
        guard hasActiveSession, seconds.isFinite else { return }
        let upperBound = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? .greatestFiniteMagnitude
        let target = min(max(seconds, 0), upperBound)
        let identity = progressIdentity
        let token = UUID()
        seekToken = token
        seekError = nil
        seekSettlingUntil = Date().addingTimeInterval(1.5)
        referenceElapsedTime = target
        referenceDate = Date()
        elapsedTime = target
        if bundleIdentifier == "com.apple.Music" {
            seekInFlight = true
            let expectedTitle = title
            let expectedArtist = artist
            musicQueue.async { [weak self] in
                let (state, error) = AppleMusicPlayer.seek(to: target, expectedTitle: expectedTitle, expectedArtist: expectedArtist)
                DispatchQueue.main.async {
                    guard let self, self.seekToken == token else { return }
                    self.seekInFlight = false
                    guard self.progressIdentity == identity else { return }
                    self.seekSettlingUntil = .distantPast
                    if let state {
                        self.lastSeekSampledAt = state.sampledAt
                        self.referenceElapsedTime = state.position + (state.playing ? max(0, ProcessInfo.processInfo.systemUptime - state.sampledAt) : 0)
                        self.referenceDate = Date()
                        self.applyMusicState(state.playing)
                    } else {
                        self.seekError = error == -1743
                            ? String(localized: "需要允许 Cueto 控制音乐，请在系统设置的自动化中授权。")
                            : String(localized: "未能跳转，请重试")
                        self.nextMusicMetadataRead = .distantPast
                        self.refreshMusicMetadata()
                        self.media.getTrackInfo { [weak self] info in self?.receive(info) }
                    }
                }
            }
        } else {
            seekInFlight = false
            media.setTime(seconds: target)
            for delay in [0.35, 1.6] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.seekToken == token, self.progressIdentity == identity else { return }
                    self.media.getTrackInfo { [weak self] info in self?.receive(info) }
                }
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
        refreshMusicMetadata()
        refreshMusicState()
        elapsedTime = currentElapsedTime
    }

    private func receive(_ info: TrackInfo?) {
        guard let payload = info?.payload else {
            if hasRecentMusicState { return }
            if adoptRunningAudioSourceIfNeeded() {
                return
            }
            if pendingPlaybackState != nil, Date() < pendingStateDeadline {
                return
            }
            applicationName = String(localized: "未在播放")
            bundleIdentifier = nil
            title = nil
            artist = nil
            isPlaying = false
            hasActiveSession = false
            applicationIcon = nil
            clearArtwork()
            elapsedTime = nil
            duration = nil
            referenceElapsedTime = nil
            playbackRate = 0
            refreshActiveAudioSources()
            refreshAvailableAudioSources()
            return
        }

        let systemReportedPlaying = payload.isPlaying ?? ((payload.playbackRate ?? 0) > 0)
        if let target = cosmosPendingPlayback,
           payload.bundleIdentifier != "app.podcast.cosmos" || systemReportedPlaying == target {
            finishCosmosPlaybackRequest()
        }
        let reportedPlaying = payload.bundleIdentifier == "com.apple.Music" && hasRecentMusicState
            ? (confirmedMusicPlaying ?? systemReportedPlaying) : systemReportedPlaying
        if let identifier = payload.bundleIdentifier {
            audioActivityPolicy.report(bundleIdentifier: identifier, playing: reportedPlaying)
            audioSourceMonitor.rememberMediaSource(
                processID: payload.PID ?? 0,
                bundleIdentifier: identifier,
                applicationName: payload.applicationName?.nonEmpty ?? sourceName(for: identifier)
            )
        }
        if let identifier = payload.bundleIdentifier,
           excludedApps.bundleIdentifiers.contains(identifier) {
            if adoptRunningAudioSourceIfNeeded(excluding: identifier) { return }
            clearDisplayedSource()
            return
        }
        if hasRecentMusicState, payload.bundleIdentifier != "com.apple.Music", !reportedPlaying {
            return
        }
        if payload.bundleIdentifier != "com.apple.Music", reportedPlaying { confirmedMusicPlaying = nil }
        if !reportedPlaying,
           let payloadBundleIdentifier = payload.bundleIdentifier,
           adoptRunningAudioSourceIfNeeded(excluding: payloadBundleIdentifier) {
            return
        }

        if bundleIdentifier != payload.bundleIdentifier {
            musicMetadataGeneration = UUID()
            musicArtworkKey = nil
            nextMusicMetadataRead = .distantPast
            nextMusicArtworkRead = .distantPast
        }
        let incompleteMusicInfo = payload.bundleIdentifier == "com.apple.Music" &&
            (payload.title?.nonEmpty == nil || payload.artworkDataBase64 == nil)
        if incompleteMusicInfo, bundleIdentifier == "com.apple.Music", musicArtworkKey != nil {
            needsMusicMetadata = true
            if title == payload.title?.nonEmpty || payload.title?.nonEmpty == nil { return }
        }
        if !incompleteMusicInfo {
            needsMusicMetadata = false
            musicMetadataGeneration = UUID()
        }
        let previousIdentity = progressIdentity
        applicationName = payload.applicationName?.nonEmpty ?? sourceName(for: payload.bundleIdentifier)
        if bundleIdentifier != payload.bundleIdentifier || artworkData != payload.artworkDataBase64 {
            artworkData = payload.artworkDataBase64
            artwork = payload.artwork
        }
        bundleIdentifier = payload.bundleIdentifier
        title = payload.title?.nonEmpty
        artist = payload.artist?.nonEmpty
        if let pendingPlaybackState {
            if reportedPlaying == pendingPlaybackState || Date() >= pendingStateDeadline {
                self.pendingPlaybackState = nil
                isPlaying = reportedPlaying
            }
        } else {
            isPlaying = reportedPlaying
        }
        hasActiveSession = true
        needsMusicMetadata = incompleteMusicInfo
        applicationIcon = icon(for: payload.bundleIdentifier)
        duration = payload.durationMicros.map { $0 / 1_000_000 }
        let reportedTime = payload.currentElapsedTime ?? payload.elapsedTimeMicros.map { $0 / 1_000_000 }
        let sameItem = previousIdentity == progressIdentity
        if !sameItem {
            seekError = nil
            seekSettlingUntil = .distantPast
        }
        // Ignore a stale pre-seek position while the player acknowledges the command.
        let acknowledgesSeek = reportedTime.map { abs($0 - (currentElapsedTime ?? $0)) < 2 } ?? false
        if !sameItem || (!seekInFlight && (Date() >= seekSettlingUntil || acknowledgesSeek)) {
            referenceElapsedTime = reportedTime
            referenceDate = Date()
            seekSettlingUntil = .distantPast
        }
        playbackRate = reportedPlaying ? (payload.playbackRate ?? 1) : 0
        refreshActiveAudioSources(processID: payload.PID)
        refreshAvailableAudioSources()
        refreshDisplayedProgress()
    }

    private func reconcileDisplayedSourceWithRunningAudio() {
        if hasRecentMusicState, confirmedMusicPlaying == true {
            refreshActiveAudioSources()
            return
        }
        if let bundleIdentifier,
           !excludedApps.bundleIdentifiers.contains(bundleIdentifier),
           playbackCandidates.contains(where: { $0.bundleIdentifier == bundleIdentifier }) {
            refreshActiveAudioSources()
            return
        }

        if adoptRunningAudioSourceIfNeeded(excluding: bundleIdentifier) {
            return
        }

        if let bundleIdentifier, excludedApps.bundleIdentifiers.contains(bundleIdentifier) {
            clearDisplayedSource()
        } else {
            refreshActiveAudioSources()
        }
    }

    @discardableResult
    private func adoptRunningAudioSourceIfNeeded(excluding excludedBundleIdentifier: String? = nil) -> Bool {
        guard let source = playbackCandidates.first(where: {
            $0.bundleIdentifier != excludedBundleIdentifier
                && !excludedApps.bundleIdentifiers.contains($0.bundleIdentifier)
        }) else {
            return false
        }

        let sourceChanged = bundleIdentifier != source.bundleIdentifier
        applicationName = source.applicationName
        bundleIdentifier = source.bundleIdentifier
        applicationIcon = source.icon
        isPlaying = true
        hasActiveSession = true
        needsMusicMetadata = source.bundleIdentifier == "com.apple.Music"
        if sourceChanged || source.bundleIdentifier != "com.apple.Music" {
            musicMetadataGeneration = UUID()
            musicArtworkKey = nil
            nextMusicMetadataRead = .distantPast
            nextMusicArtworkRead = .distantPast
            clearArtwork()
            title = nil
            artist = nil
            elapsedTime = nil
            duration = nil
            referenceElapsedTime = nil
            playbackRate = 1
            pendingPlaybackState = nil
        }
        refreshMusicMetadata()
        refreshActiveAudioSources(processID: source.processID)
        refreshAvailableAudioSources()
        return true
    }

    private func refreshActiveAudioSources(processID: pid_t? = nil) {
        var sources = playbackCandidates.filter {
            !excludedApps.bundleIdentifiers.contains($0.bundleIdentifier)
        }
        if hasActiveSession, isPlaying,
           let bundleIdentifier,
           !excludedApps.bundleIdentifiers.contains(bundleIdentifier),
           !sources.contains(where: { $0.bundleIdentifier == bundleIdentifier }) {
            sources.append(
                ActiveAudioSource(
                    processID: processID ?? 0,
                    bundleIdentifier: bundleIdentifier,
                    applicationName: applicationName
                )
            )
        }
        sources.sort { left, right in
            if left.bundleIdentifier == bundleIdentifier { return true }
            if right.bundleIdentifier == bundleIdentifier { return false }
            return left.applicationName.localizedStandardCompare(right.applicationName) == .orderedAscending
        }
        if sources != activeAudioSources {
            activeAudioSources = sources
        }
    }

    private func refreshAvailableAudioSources() {
        var sources = detectedProcessSources.filter {
            !excludedApps.bundleIdentifiers.contains($0.bundleIdentifier)
        }
        if hasActiveSession,
           let bundleIdentifier,
           !excludedApps.bundleIdentifiers.contains(bundleIdentifier),
           !sources.contains(where: { $0.bundleIdentifier == bundleIdentifier }) {
            sources.append(ActiveAudioSource(
                processID: 0,
                bundleIdentifier: bundleIdentifier,
                applicationName: applicationName,
                isRunningOutput: detectedAudioSources.contains { $0.bundleIdentifier == bundleIdentifier }
            ))
        }
        sources.sort { left, right in
            if left.isRunningOutput != right.isRunningOutput { return left.isRunningOutput }
            return left.applicationName.localizedStandardCompare(right.applicationName) == .orderedAscending
        }
        if sources != availableAudioSources {
            availableAudioSources = sources
        }
    }

    private func clearDisplayedSource() {
        needsMusicMetadata = false
        musicMetadataGeneration = UUID()
        musicArtworkKey = nil
        confirmedMusicPlaying = nil
        applicationName = String(localized: "未在播放")
        bundleIdentifier = nil
        title = nil
        artist = nil
        isPlaying = false
        hasActiveSession = false
        applicationIcon = nil
        clearArtwork()
        elapsedTime = nil
        duration = nil
        referenceElapsedTime = nil
        playbackRate = 0
        pendingPlaybackState = nil
        refreshActiveAudioSources()
        refreshAvailableAudioSources()
    }

    private func clearArtwork() {
        artworkData = nil
        if artwork != nil { artwork = nil }
    }

    private func sourceName(for bundleIdentifier: String?) -> String {
        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return String(localized: "正在播放")
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
