import Foundation

nonisolated struct MenuBarSubtitleContent: Equatable {
    let text: String
    let sourceIdentifier: String
    let isMetadata: Bool
    var scrollTimeBudget: TimeInterval? = nil
    var scrollStyle: SubtitleScrollStyle = .music
    var scrollSpeed: SubtitleScrollSpeed = .normal

    static func == (lhs: Self, rhs: Self) -> Bool {
        // The remaining cue time changes during playback. It must not trigger
        // a new transition or restart scrolling on each player sample.
        lhs.text == rhs.text && lhs.sourceIdentifier == rhs.sourceIdentifier &&
            lhs.isMetadata == rhs.isMetadata && lhs.scrollStyle == rhs.scrollStyle && lhs.scrollSpeed == rhs.scrollSpeed
    }

    static func make(lyric: String?, title: String?, artist: String?, sourceIdentifier: String, sourceName: String,
                     scrollTimeBudget: TimeInterval? = nil, scrollStyle: SubtitleScrollStyle = .music,
                     scrollSpeed: SubtitleScrollSpeed = .normal) -> Self {
        func clean(_ value: String?) -> String? {
            guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return text
        }
        if let lyric = clean(lyric) {
            return Self(text: lyric, sourceIdentifier: sourceIdentifier, isMetadata: false,
                        scrollTimeBudget: scrollTimeBudget, scrollStyle: scrollStyle, scrollSpeed: scrollSpeed)
        }
        var metadata: [String] = []
        for value in [clean(title), clean(artist)].compactMap({ $0 }) where !metadata.contains(value) {
            metadata.append(value)
        }
        return Self(text: metadata.isEmpty ? "♪ \(sourceName)" : metadata.joined(separator: " · "),
                    sourceIdentifier: sourceIdentifier, isMetadata: true, scrollStyle: scrollStyle, scrollSpeed: scrollSpeed)
    }
}

/// Metadata is only an introduction. Once lyrics begin, gaps become silence.
nonisolated struct MenuBarSubtitleContinuity {
    private var displayed: MenuBarSubtitleContent?
    private var identity: [String?] = []
    private var hasShownLyric = false
    private(set) var refreshAt: Date?

    mutating func resolve(_ incoming: MenuBarSubtitleContent?, trackIdentity: [String?], at now: Date,
                         hasEnteredLyrics: Bool = false) -> MenuBarSubtitleContent? {
        if identity != trackIdentity || incoming == nil {
            displayed = nil
            refreshAt = nil
            hasShownLyric = false
        }
        identity = trackIdentity
        if hasEnteredLyrics || (incoming.map { !$0.isMetadata && !$0.text.isEmpty } ?? false) {
            hasShownLyric = true
        }
        if let incoming, let previous = displayed,
           !previous.isMetadata, !previous.text.isEmpty, incoming.isMetadata,
           previous.sourceIdentifier == incoming.sourceIdentifier, identity == trackIdentity {
            let deadline = refreshAt ?? now.addingTimeInterval(0.65)
            refreshAt = deadline
            if now < deadline { return previous }
        }
        let resolved: MenuBarSubtitleContent?
        if let incoming, incoming.isMetadata, hasShownLyric {
            resolved = MenuBarSubtitleContent(text: "", sourceIdentifier: incoming.sourceIdentifier, isMetadata: false,
                                              scrollStyle: incoming.scrollStyle, scrollSpeed: incoming.scrollSpeed)
        } else {
            resolved = incoming
        }
        displayed = resolved
        refreshAt = nil
        return resolved
    }
}
