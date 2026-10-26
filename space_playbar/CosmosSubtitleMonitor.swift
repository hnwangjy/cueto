#if os(macOS)
import AppKit
import ApplicationServices
import Combine

enum SubtitleWidth: String, CaseIterable {
    case short, medium, long

    var title: String {
        switch self {
        case .short: return "短"
        case .medium: return "适中"
        case .long: return "长"
        }
    }

    var points: CGFloat {
        switch self {
        case .short: return 180
        case .medium: return 240
        case .long: return 320
        }
    }
}

/// Reads the caption region observed in Xiaoyuzhou's playback page.
/// Never navigates, clicks, captures audio, or reads another application's UI.
@MainActor
final class CosmosSubtitleMonitor: ObservableObject {
    @Published var width: SubtitleWidth {
        didSet { UserDefaults.standard.set(width.rawValue, forKey: "subtitleWidth") }
    }
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "showCosmosSubtitles")
            generation = UUID()
            currentText = nil
            configureTimer()
            refresh()
        }
    }
    @Published private(set) var currentText: String?
    @Published private(set) var needsPermission = false
    @Published private(set) var statusMessage = "开启后，在菜单栏显示小宇宙当前字幕"

    private var timer: AnyCancellable?
    private let readerQueue = DispatchQueue(label: "com.wangjiayuan.cueto.subtitles", qos: .utility)
    private var isReading = false
    private var generation = UUID()
    private let windowCache = CaptionWindowCache()

    init() {
        width = SubtitleWidth(rawValue: UserDefaults.standard.string(forKey: "subtitleWidth") ?? "") ?? .medium
        isEnabled = UserDefaults.standard.bool(forKey: "showCosmosSubtitles")
        configureTimer()
        refresh()
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
    }

    private func configureTimer() {
        timer = nil
        guard isEnabled else { return }
        timer = Timer.publish(every: 0.6, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        guard isEnabled else {
            currentText = nil
            needsPermission = false
            statusMessage = "开启后，在菜单栏显示小宇宙当前字幕"
            return
        }
        needsPermission = !AXIsProcessTrusted()
        guard !needsPermission else {
            currentText = nil
            statusMessage = "需要辅助功能授权，用于读取小宇宙播放页的字幕文字"
            return
        }
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "app.podcast.cosmos"
              }) else {
            currentText = nil
            statusMessage = "请启动小宇宙并打开默认播放页"
            return
        }
        guard !isReading else { return }
        isReading = true
        let token = generation
        let pid = app.processIdentifier
        let cache = windowCache
        readerQueue.async { [weak self] in
            let text = Self.readCaption(processID: pid, cache: cache)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isReading = false
                guard self.generation == token, self.isEnabled else { return }
                if self.currentText != text { self.currentText = text }
                let message = text == nil
                    ? "请回到小宇宙默认播放页，显示封面下方的小字幕"
                    : "正在读取默认播放页的小字幕"
                if self.statusMessage != message { self.statusMessage = message }
            }
        }
    }

    nonisolated private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    nonisolated private static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    nonisolated private static func text(_ element: AXUIElement) -> String? {
        for key in [kAXDescriptionAttribute, kAXValueAttribute, kAXTitleAttribute] {
            if let value = attribute(element, key) as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    nonisolated static func captionLine(_ lines: [String]) -> String? {
        // Only the compact caption block. Never concatenate neighbouring rows.
        guard (1...3).contains(lines.count) else { return nil }
        if lines.count == 1 {
            let line = lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.hasSuffix("人正在听"), line != "99+",
                  line.range(of: "^[0-9]+[+]?$", options: .regularExpression) == nil else { return nil }
        }
        let value = lines[lines.count / 2]
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !value.isEmpty, value.count <= 500 else { return nil }
        return value
    }

    nonisolated private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute),
              let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }

    nonisolated private static func readCaption(processID: pid_t, cache: CaptionWindowCache) -> String? {
        let app = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(app, 0.15)
        var windows = (attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        for key in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            if let value = attribute(app, key), CFGetTypeID(value) == AXUIElementGetTypeID() {
                let window = value as! AXUIElement
                if !windows.contains(where: { CFEqual($0, window) }) { windows.append(window) }
            }
        }
        // AXWindows may omit a live window after switching Spaces. Keep only a
        // previously discovered, still-valid window belonging to this same process.
        if cache.processID != processID {
            cache.windows = []
            cache.processID = processID
        }
        for window in cache.windows where attribute(window, kAXRoleAttribute) as? String == kAXWindowRole {
            if !windows.contains(where: { CFEqual($0, window) }) { windows.append(window) }
        }
        cache.windows = Array(windows.prefix(4))
        let deadline = ProcessInfo.processInfo.systemUptime + 0.8
        var visited = 0
        var candidates: [String] = []

        func captionFragments(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement]? {
            guard depth < 6, ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            let role = attribute(element, kAXRoleAttribute) as? String
            if role == kAXStaticTextRole { return text(element) == nil ? nil : [element] }
            guard role == kAXGroupRole else { return nil }
            var result: [AXUIElement] = []
            for child in children(element) {
                guard let fragments = captionFragments(child, depth: depth + 1) else { return nil }
                result.append(contentsOf: fragments)
                guard result.count <= 3 else { return nil }
            }
            return result
        }

        func visit(_ element: AXUIElement, depth: Int) {
            guard depth < 14, visited < 160,
                  ProcessInfo.processInfo.systemUptime < deadline else { return }
            visited += 1
            let items = children(element)
            let roles = items.map { attribute($0, kAXRoleAttribute) as? String ?? "" }
            let hasProgress = zip(items, roles).contains {
                $0.1 == kAXSliderRole && text($0.0) == "播放进度"
            }
            let hasTransport = zip(items, roles).contains {
                $0.1 == kAXButtonRole && text($0.0) == "后退15秒"
            }
            if hasProgress && hasTransport {
                // In the compact cover layout the episode title follows the back
                // button. In the expanded transcript it precedes it. Fail closed
                // on a different layout instead of reading transcript context.
                guard let backIndex = items.firstIndex(where: { text($0) == "返回上一页" }),
                      let titleIndex = items.indices.first(where: {
                          roles[$0] == kAXStaticTextRole && $0 > backIndex && text(items[$0]) != nil
                      }), titleIndex > backIndex else { return }
                for (item, role) in zip(items.prefix(backIndex), roles.prefix(backIndex)) where role == kAXGroupRole {
                    if let lines = captionFragments(item), let fallback = captionLine(lines.compactMap({ text($0) })) {
                        // Read the row nearest the compact viewport's centre, not the
                        // first accessibility child (which can be the outgoing row).
                        if let viewport = frame(item),
                           let central = lines.compactMap({ line -> (String, CGFloat)? in
                               guard let bounds = frame(line), bounds.intersects(viewport), let value = text(line) else { return nil }
                               return (value, abs(bounds.midY - viewport.midY))
                           }).min(by: { $0.1 < $1.1 }) {
                            candidates.append(central.0)
                        } else {
                            candidates.append(fallback)
                        }
                    }
                }
                return
            }
            for (item, role) in zip(items, roles) where role == kAXGroupRole || role == kAXWindowRole {
                visit(item, depth: depth + 1)
            }
        }
        for window in (windows.isEmpty ? children(app) : windows).prefix(4) { visit(window, depth: 0) }
        return candidates.count == 1 ? candidates[0] : nil
    }
}

/// Accessed exclusively on CosmosSubtitleMonitor's serial reader queue.
private final class CaptionWindowCache: @unchecked Sendable {
    nonisolated(unsafe) var processID: pid_t?
    nonisolated(unsafe) var windows: [AXUIElement] = []
    nonisolated init() {}
}
#endif
