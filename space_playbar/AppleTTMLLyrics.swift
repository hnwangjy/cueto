import Foundation

enum AppleTTMLLyrics {
    nonisolated static func parse(_ source: String) -> [LyricCue] {
        let reader = Reader()
        let parser = XMLParser(data: Data(source.utf8))
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse() else { return [] }
        let lines = reader.lines.enumerated().sorted {
            $0.element.cue.time == $1.element.cue.time ? $0.offset < $1.offset : $0.element.cue.time < $1.element.cue.time
        }.map(\.element)
        var cues: [LyricCue] = []
        for (index, line) in lines.enumerated() {
            cues.append(line.cue)
            // An earlier line ending must not clear a line that already started.
            let nextStart = index + 1 < lines.count ? lines[index + 1].cue.time : .infinity
            if let end = line.end, end.isFinite, end > line.cue.time, end < nextStart {
                cues.append(LyricCue(time: end, text: ""))
            }
        }
        return cues
    }

    nonisolated static func seconds(_ value: String) -> Double? {
        if value.hasSuffix("ms") { return Double(value.dropLast(2)).map { $0 / 1000 } }
        if value.hasSuffix("s") { return Double(value.dropLast()) }
        let parts = value.split(separator: ":").compactMap { Double($0) }
        guard parts.count == value.split(separator: ":").count, (1...3).contains(parts.count) else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    nonisolated private final class Reader: NSObject, XMLParserDelegate {
        var lines: [(cue: LyricCue, end: Double?)] = []
        var begin: Double?
        var end: Double?
        var text = ""
        var depth = 0
        var metadataDepth = 0

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            if name == "metadata" || name == "head" { metadataDepth += 1 }
            guard metadataDepth == 0 else { return }
            if name == "p", depth == 0 {
                begin = attributes["begin"].flatMap(AppleTTMLLyrics.seconds)
                end = attributes["end"].flatMap(AppleTTMLLyrics.seconds)
                text = ""
                depth = 1
            } else if depth > 0 {
                depth += 1
                if name == "br" { text += " " }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if depth > 0, metadataDepth == 0 { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "metadata" || name == "head" { metadataDepth -= 1; return }
            guard metadataDepth == 0, depth > 0 else { return }
            depth -= 1
            if depth == 0, let begin, begin.isFinite, begin >= 0 {
                let line = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty {
                    lines.append((LyricCue(time: begin, text: line), end))
                }
            }
        }
    }
}
