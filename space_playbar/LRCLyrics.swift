import Foundation

struct LyricCue: Codable, Equatable, Sendable {
    let time: TimeInterval
    let text: String
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

    nonisolated static func line(at position: TimeInterval, in cues: [LyricCue]) -> String? {
        guard position.isFinite else { return nil }
        var low = 0
        var high = cues.count
        while low < high {
            let middle = (low + high) / 2
            if cues[middle].time <= position { low = middle + 1 } else { high = middle }
        }
        guard low > 0, !cues[low - 1].text.isEmpty else { return nil }
        return cues[low - 1].text
    }
}
