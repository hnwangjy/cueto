#if os(macOS) && CUETO_APPLE_MUSIC_LYRICS
import AppKit
import Combine
import MusicKit
import SwiftUI
import WebKit

struct AppleMusicProbeTrack: Sendable {
    let key: String
    let title: String
    let artist: String
    let album: String
    let duration: Double
}

enum AppleMusicDirectError: Error, LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case .unavailable(let message): return message }
    }
}

/// Apple's web client owns credentials in the app's persistent WebKit store.
/// No cookie/token extraction or password collection.
@MainActor
final class AppleMusicDirectProbe: NSObject, ObservableObject, WKNavigationDelegate, NSWindowDelegate {
    @Published private(set) var status = "请在苹果页面登录后，读取当前歌曲。"
    @Published private(set) var busy = false
    @Published private(set) var lineCount = 0
    @Published private(set) var isConnected = false
    @Published private(set) var accountSummary = "未连接"
    let webView: WKWebView
    var currentTrack: (() -> AppleMusicProbeTrack?)?
    var onLyrics: ((String, [LyricCue]) -> Void)?
    var onSessionConnected: (() -> Void)?
    var onSessionDisconnected: (() -> Void)?
    private var window: NSWindow?
    private var operation: Task<Void, Never>?
    private var sessionTimer: AnyCancellable?
    private var checkingSession = false
    private var sessionRevision = UUID()

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.inactiveSchedulingPolicy = .throttle
        // A zero-sized, unattached view may leave the web player's initialization
        // waiting for layout until its connection window is shown.
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 680), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        prepareWindow()
    }

    func open() {
        startSessionObservation()
        prepareWindow()
        guard let window else { return }
        if window.contentView === webView { window.contentView = NSHostingView(rootView: ProbeView(probe: self)) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if webView.url == nil { login() }
    }

    private func prepareWindow() {
        guard window == nil else { return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 780),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "连接 Apple Music"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = webView
        self.window = window
        window.center()
        // Attach/layout the view at launch without ordering the window on screen.
        // The authenticated client must be initialized before the user opens UI.
        window.contentView?.layoutSubtreeIfNeeded()
    }

    func login() {
        operation?.cancel()
        busy = false
        status = "正在恢复 Apple Music 登录；未登录时请在苹果页面完成登录。"
        webView.load(URLRequest(url: URL(string: "https://music.apple.com/")!))
        startSessionObservation()
    }

    func openMusic() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    func disconnect() {
        operation?.cancel()
        sessionRevision = UUID()
        sessionTimer = nil
        isConnected = false
        accountSummary = "未连接"
        onSessionDisconnected?()
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        busy = true
        status = "正在清除 Cueto 的 Apple Music 登录…"
        let store = webView.configuration.websiteDataStore
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { [weak self] records in
            let apple = records.filter { $0.displayName == "apple.com" || $0.displayName.hasSuffix(".apple.com") }
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: apple) {
                Task { @MainActor [weak self] in
                    self?.busy = false
                    self?.status = "已断开。音乐应用和其他浏览器的登录不受影响。"
                }
            }
        }
    }

    private func startSessionObservation() {
        sessionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self, self.window?.isVisible == true, !self.checkingSession, !self.busy else { return }
                self.checkingSession = true
                Task { [weak self] in
                    guard let self else { return }
                    defer { self.checkingSession = false }
                    _ = try? await self.inspectSession()
                }
            }
    }

    private func inspectSession() async throws -> Bool {
        guard webView.url?.scheme == "https", webView.url?.host == "music.apple.com", !webView.isLoading else { return false }
        let revision = sessionRevision
        let value = try await webView.evaluateJavaScript("(() => { const k = globalThis.MusicKit?.getInstance?.(); return {ready: !!k?.api?.music, authorized: !!k?.isAuthorized, region: k?.storefrontId || ''}; })()")
        guard revision == sessionRevision, let info = value as? [String: Any], info["ready"] as? Bool == true else { return false }
        if info["authorized"] as? Bool == true {
            let newlyConnected = !isConnected
            isConnected = true
            let region = (info["region"] as? String ?? "").uppercased()
            accountSummary = region.isEmpty ? "已连接 Apple Music" : "已连接 · \(region)"
            if newlyConnected {
                status = "已恢复登录，正在读取当前歌曲歌词。"
                onSessionConnected?()
            }
            return true
        }
        isConnected = false
        accountSummary = "需要登录"
        return false
    }

    private func restoreSession() async throws {
        if webView.url == nil { webView.load(URLRequest(url: URL(string: "https://music.apple.com/")!)) }
        for _ in 0..<60 {
            try Task.checkCancellation()
            if (try? await inspectSession()) == true { return }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw AppleMusicDirectError.unavailable("请连接 Apple Music，完成登录后会自动继续。")
    }

    func testMusicKit() {
        guard !busy else { return }
        busy = true
        status = "正在验证本应用的 MusicKit 开发者凭据…"
        operation = Task { [weak self] in
            do {
                // Do not harvest Apple's website developer token or log credentials.
                _ = try await MusicDataRequest.tokenProvider.developerToken(options: [])
                guard !Task.isCancelled, let self else { return }
                self.status = "本应用的 MusicKit 开发者凭据可用；这尚不证明具备歌词权限。"
                self.busy = false
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.status = "本应用暂时无法取得 MusicKit 开发者凭据（\((error as NSError).code)）；网页直连可单独测试。"
                self.busy = false
            }
        }
    }

    func readLyrics() {
        guard !busy else { return }
        guard let track = currentTrack?() else { status = "请先在 Mac 的音乐应用播放一首歌曲。"; return }
        guard webView.url?.scheme == "https", webView.url?.host == "music.apple.com" else {
            status = "请先回到 Apple Music 页面并完成登录。"; return
        }
        busy = true
        lineCount = 0
        status = "正在通过苹果网页会话读取歌词…"
        operation = Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false }
            do {
                let cues = try await self.fetchLyrics(for: track)
                let count = cues.filter { !$0.text.isEmpty }.count
                guard self.currentTrack?()?.key == track.key else { self.status = "歌曲已切换，请重新读取。"; return }
                self.lineCount = count
                self.onLyrics?(track.key, cues)
                self.status = "直连成功：\(count) 行同步歌词，已用于当前歌曲。"
            } catch {
                guard !Task.isCancelled else { return }
                // WebKit errors may contain webpage request details. Keep them out of logs/UI.
                self.status = (error as? AppleMusicDirectError)?.localizedDescription
                    ?? "网页会话读取失败（\((error as NSError).code)）。请确认已登录并拥有有效订阅。"
            }
        }
    }

    func fetchLyrics(for track: AppleMusicProbeTrack) async throws -> [LyricCue] {
        // Only request full scheduling while restoring/requesting, then yield CPU
        // again. No need to show a window just to initialize the authenticated page.
        webView.configuration.preferences.inactiveSchedulingPolicy = .none
        defer { webView.configuration.preferences.inactiveSchedulingPolicy = .throttle }
        try await restoreSession()
        let value = try await webView.callAsyncJavaScript(Self.script,
            arguments: ["title": track.title, "artist": track.artist, "album": track.album, "duration": track.duration],
            in: nil, contentWorld: .page)
        try Task.checkCancellation()
        guard let result = value as? [String: Any] else {
            throw AppleMusicDirectError.unavailable("苹果网页没有返回可识别的结果。")
        }
        guard let ttml = result["ttml"] as? String else {
            throw AppleMusicDirectError.unavailable(result["message"] as? String ?? "未取得苹果歌词。")
        }
        let cues = AppleTTMLLyrics.parse(ttml)
        guard cues.contains(where: { !$0.text.isEmpty }) else {
            throw AppleMusicDirectError.unavailable("已收到苹果歌词，但时间轴格式暂不支持。")
        }
        return cues
    }

    func windowWillClose(_ notification: Notification) { operation?.cancel(); busy = false; sessionTimer = nil }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let host = url.host?.lowercased() ?? ""
        let allowed = url.scheme == "https" && (host == "apple.com" || host.hasSuffix(".apple.com"))
        decisionHandler(allowed || url.absoluteString == "about:blank" ? .allow : .cancel)
    }

    private static let script = #"""
    const kit = globalThis.MusicKit?.getInstance?.();
    if (!kit?.api?.music) return {message: "苹果网页播放器尚未就绪，请等待页面加载完成。"};
    if (!kit.isAuthorized) return {message: "请先在苹果页面登录 Apple Music。"};
    const region = kit.storefrontId;
    if (!region || !/^[a-z]{2}$/i.test(region)) return {message: "无法确认账号地区，请先在网页中打开音乐资料库。"};
    const request = async (path, params = {}) => {
        let timer;
        try {
            const response = await Promise.race([
                kit.api.music(path, params),
                new Promise((_, reject) => { timer = setTimeout(() => reject({status: 408}), 20000); })
            ]);
            return response?.data ?? response;
        } finally { clearTimeout(timer); }
    };
    const normalize = s => String(s ?? "").normalize("NFKD").toLowerCase().replace(/[^\p{L}\p{N}]/gu, "");
    const performer = s => normalize(s) === "abeltesfaye" ? "theweeknd" : normalize(s);
    const found = await request(`/v1/catalog/${region}/search`, {term: `${title} ${artist}`, types: "songs", limit: 25});
    const candidates = (found?.results?.songs?.data ?? []).filter(item => {
        const a = item.attributes ?? {};
        return normalize(a.name) === normalize(title) && performer(a.artistName) === performer(artist)
            && Number.isFinite(a.durationInMillis) && Math.abs(a.durationInMillis / 1000 - duration) <= 2;
    });
    candidates.sort((x,y) => {
        const ax = x.attributes, ay = y.attributes;
        const albumRank = Number(normalize(ay.albumName) === normalize(album)) - Number(normalize(ax.albumName) === normalize(album));
        return albumRank || Math.abs(ax.durationInMillis / 1000 - duration) - Math.abs(ay.durationInMillis / 1000 - duration);
    });
    if (!candidates.length) return {message: "苹果目录中未确认当前歌曲版本；尚未请求歌词。"};
    const song = candidates[0];
    for (const kind of ["syllable-lyrics", "lyrics"]) {
        try {
            const result = await request(`/v1/catalog/${region}/songs/${encodeURIComponent(song.id)}/${kind}`);
            const a = result?.data?.[0]?.attributes;
            const ttml = a?.ttmlLocalizations ?? a?.ttml;
            if (typeof ttml === "string" && ttml.includes("<")) return {ttml};
        } catch (error) {
            const status = Number(error?.status ?? error?.response?.status ?? 0);
            if (status === 401 || status === 403) return {message: `苹果歌词请求被拒绝（HTTP ${status}）。普通网页登录尚不足以访问此接口。`};
            if (status && status !== 404) return {message: `苹果歌词服务返回 HTTP ${status}。`};
        }
    }
    return {message: "已确认歌曲，但网页会话未返回同步歌词；不能据此区分曲目缺失和内部接口权限限制。"};
    """#
}

private struct ProbeView: View {
    @ObservedObject var probe: AppleMusicDirectProbe
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(probe.accountSummary).font(.headline)
                Spacer()
                Button("打开音乐", action: probe.openMusic)
                Button("重新连接", action: probe.login)
                Button("断开连接", action: probe.disconnect)
                Button("读取当前歌曲歌词", action: probe.readLyrics).buttonStyle(.borderedProminent)
            }.disabled(probe.busy)
            Text(probe.status).font(.callout).textSelection(.enabled)
            ProbeWebView(webView: probe.webView)
        }.padding(14).frame(minWidth: 760, minHeight: 600)
    }
}

private struct ProbeWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif
