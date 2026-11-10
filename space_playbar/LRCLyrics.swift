import Foundation

nonisolated struct LyricCue: Codable, Equatable, Sendable {
    let time: TimeInterval
    let text: String
}

nonisolated struct LyricContext: Equatable, Sendable {
    var previous: LyricCue?
    var current: LyricCue?
    var next: LyricCue?
}

struct LyricMatchCandidate: Decodable, Sendable {
    let trackName: String
    let artistName: String
    let albumName: String
    let duration: Double
    let syncedLyrics: String?
    let instrumental: Bool?
}

extension LyricMatchCandidate {
    // Some search records have null metadata. Keep valid siblings usable;
    // unknown duration is explicitly rejected by the matching policy below.
    private enum CodingKeys: String, CodingKey {
        case trackName, artistName, albumName, duration, syncedLyrics, instrumental
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        trackName = try values.decodeIfPresent(String.self, forKey: .trackName) ?? ""
        artistName = try values.decodeIfPresent(String.self, forKey: .artistName) ?? ""
        albumName = try values.decodeIfPresent(String.self, forKey: .albumName) ?? ""
        duration = try values.decodeIfPresent(Double.self, forKey: .duration) ?? .nan
        syncedLyrics = try values.decodeIfPresent(String.self, forKey: .syncedLyrics)
        instrumental = try values.decodeIfPresent(Bool.self, forKey: .instrumental)
    }
}

enum LyricMatching {
    nonisolated static func artist(_ value: String) -> String {
        let key = normalized(value)
        // Apple Music can use the artist's legal name while older lyric records
        // retain the established stage name. Keep aliases explicit, not fuzzy.
        return key == "abeltesfaye" ? "theweeknd" : key
    }
    nonisolated static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: #"[^\p{L}\p{N}]"#, with: "", options: .regularExpression)
    }

    nonisolated static func album(_ value: String) -> String {
        normalized(value.replacingOccurrences(of: #"\s*[\(\[]deluxe(?: edition)?[\)\]]"#, with: "", options: [.regularExpression, .caseInsensitive]))
    }

    nonisolated static func select(title: String, artist: String, albumName: String, duration: Double,
                                  from candidates: [LyricMatchCandidate]) -> LyricMatchCandidate? {
        let ranked = candidates.compactMap { candidate -> (LyricMatchCandidate, Int)? in
            guard normalized(candidate.trackName) == normalized(title),
                  candidate.duration.isFinite, abs(candidate.duration - duration) <= 2,
                  let lrc = candidate.syncedLyrics, !LRCLyrics.parse(lrc).isEmpty else { return nil }
            let sameArtist = self.artist(candidate.artistName) == self.artist(artist)
            let sameAlbum = !album(albumName).isEmpty && album(candidate.albumName) == album(albumName)
            guard sameArtist || sameAlbum else { return nil }
            return (candidate, (sameArtist ? 2 : 0) + (sameAlbum ? 1 : 0))
        }
        guard let score = ranked.map({ $0.1 }).max() else { return nil }
        let finalists = ranked.filter { $0.1 == score }.map { $0.0 }
        let nearest = finalists.map { abs($0.duration - duration) }.min() ?? .infinity
        let best = finalists.filter { abs(abs($0.duration - duration) - nearest) < 0.1 }
        guard Set(best.compactMap(\.syncedLyrics)).count == 1 else { return nil }
        return best.first
    }
}

enum LRCLyrics {
    nonisolated static func parse(_ source: String) -> [LyricCue] {
        let stamp = try! NSRegularExpression(pattern: #"\[(\d+):(\d{1,2}(?:\.\d+)?)\]"#)
        let offsetPattern = try! NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#, options: .caseInsensitive)
        let raw = source as NSString
        let offset = offsetPattern.firstMatch(in: source, range: NSRange(location: 0, length: raw.length))
            .flatMap { Double(raw.substring(with: $0.range(at: 1))) }.map { $0 / 1000 } ?? 0
        var cues: [LyricCue] = []
        for line in source.components(separatedBy: .newlines) {
            let value = line as NSString
            let matches = stamp.matches(in: line, range: NSRange(location: 0, length: value.length))
            guard let last = matches.last else { continue }
            let text = value.substring(from: NSMaxRange(last.range))
                .replacingOccurrences(of: #"<\d+:\d+(?:\.\d+)?>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            for match in matches {
                guard let minutes = Double(value.substring(with: match.range(at: 1))),
                      let seconds = Double(value.substring(with: match.range(at: 2))),
                      minutes.isFinite, seconds.isFinite, seconds < 60 else { continue }
                cues.append(LyricCue(time: max(0, minutes * 60 + seconds - offset), text: text))
            }
        }
        return cues.enumerated().sorted {
            $0.element.time == $1.element.time ? $0.offset < $1.offset : $0.element.time < $1.element.time
        }.map(\.element)
    }

    nonisolated static func line(at position: TimeInterval, in cues: [LyricCue], bridgingGapsUpTo gapLimit: TimeInterval = 0) -> String? {
        activeIndex(at: position, in: cues, bridgingGapsUpTo: gapLimit).map { cues[$0].text }
    }

    nonisolated static func seekPosition(for cue: LyricCue, in cues: [LyricCue], timingOffset: TimeInterval, duration: TimeInterval) -> TimeInterval {
        // Music may round a requested position down. Land just inside the cue
        // so a paused seek does not remain in the preceding instrumental gap.
        let next = cues.first { $0.time > cue.time }?.time ?? .infinity
        let margin = min(0.03, (next - cue.time) / 2)
        return min(duration, max(0, cue.time - timingOffset + margin))
    }

    nonisolated static func context(at position: TimeInterval, in cues: [LyricCue], bridgingGapsUpTo gapLimit: TimeInterval = 0) -> LyricContext {
        guard position.isFinite else { return LyricContext() }
        let active = activeIndex(at: position, in: cues, bridgingGapsUpTo: gapLimit)
        // Keep timed silence markers out of the clickable rows, without turning
        // an instrumental gap into an active lyric. Equal-time entries follow
        // the same last-entry-wins rule as the menu-bar line lookup.
        let lines = cues.indices.filter {
            !cues[$0].text.isEmpty && ($0 + 1 == cues.count || cues[$0 + 1].time != cues[$0].time)
        }
        if let active {
            return LyricContext(previous: lines.last { $0 < active }.map { cues[$0] },
                                current: cues[active],
                                next: lines.first { $0 > active }.map { cues[$0] })
        }
        return LyricContext(previous: lines.last { cues[$0].time <= position }.map { cues[$0] },
                            next: lines.first { cues[$0].time > position }.map { cues[$0] })
    }

    nonisolated private static func activeIndex(at position: TimeInterval, in cues: [LyricCue], bridgingGapsUpTo gapLimit: TimeInterval) -> Int? {
        guard position.isFinite else { return nil }
        var low = 0
        var high = cues.count
        while low < high {
            let middle = (low + high) / 2
            if cues[middle].time <= position { low = middle + 1 } else { high = middle }
        }
        guard low > 0 else { return nil }
        let current = cues[low - 1]
        if !current.text.isEmpty { return low - 1 }

        // Keep the previous line visible across tiny gaps between timed lines.
        guard gapLimit > 0, low >= 2, low < cues.count,
              !cues[low].text.isEmpty, !cues[low - 2].text.isEmpty,
              cues[low].time - current.time <= gapLimit else { return nil }
        return low - 2
    }
}
