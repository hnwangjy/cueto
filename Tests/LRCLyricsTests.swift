import Foundation

@main
struct LRCLyricsTests {
    static func main() {
        let cues = LRCLyrics.parse("""
        [ar:Example]
        [offset:250]
        [00:10.50][00:30.500]First
        [00:20.00]Second
        [00:25.00]
        [00:60.00]invalid
        [00:40.00]<00:40.00>Word <00:40.50>timing
        """)
        assert(cues.map(\.time) == [10.25, 19.75, 24.75, 30.25, 39.75])
        assert(LRCLyrics.line(at: 0, in: cues) == nil)
        assert(LRCLyrics.line(at: 10.25, in: cues) == "First")
        assert(LRCLyrics.line(at: 24, in: cues) == "Second")
        assert(LRCLyrics.line(at: 25, in: cues) == nil)
        assert(LRCLyrics.line(at: 31, in: cues) == "First")
        assert(LRCLyrics.line(at: 40, in: cues) == "Word timing")
        // Seeking backwards re-selects from the timeline, not a stale cursor.
        assert(LRCLyrics.line(at: 20, in: cues) == "Second")
        assert(LRCLyrics.line(at: .infinity, in: cues) == nil)
        assert(LRCLyrics.line(at: 20, in: []) == nil)
        let negative = LRCLyrics.parse("[offset:-500]\n[00:01.00]Delayed")
        assert(negative == [LyricCue(time: 1.5, text: "Delayed")])
        let duplicate = LRCLyrics.parse("[00:02.00]A\n[00:02.00]B")
        assert(LRCLyrics.line(at: 2, in: duplicate) == "B")
        let albumMatch = LyricMatchCandidate(trackName: "Example", artistName: "Previous Artist Name",
            albumName: "Collection", duration: 240, syncedLyrics: "[00:01]A", instrumental: false)
        assert(LyricMatching.select(title: "Example", artist: "New Artist Name", albumName: "Collection (Deluxe)",
            duration: 241, from: [albumMatch]) != nil)
        assert(LyricMatching.select(title: "Example", artist: "Other", albumName: "Other",
            duration: 240, from: [albumMatch]) == nil)
        assert(LyricMatching.select(title: "Example", artist: "Previous Artist Name", albumName: "Collection",
            duration: 300, from: [albumMatch]) == nil)
        let conflict = LyricMatchCandidate(trackName: "Example", artistName: "Previous Artist Name",
            albumName: "Collection", duration: 240, syncedLyrics: "[00:05]A", instrumental: false)
        assert(LyricMatching.select(title: "Example", artist: "Previous Artist Name", albumName: "Collection",
            duration: 240, from: [albumMatch, conflict]) == nil)
        assert(LyricMatching.select(title: "Example (Live)", artist: "Previous Artist Name", albumName: "Collection",
            duration: 240, from: [albumMatch]) == nil)
        let alias = LyricMatchCandidate(trackName: "Example", artistName: "The Weeknd",
            albumName: "Other Collection", duration: 240, syncedLyrics: "[00:01]A", instrumental: false)
        assert(LyricMatching.select(title: "Example", artist: "Abel Tesfaye", albumName: "Another Album",
            duration: 240, from: [alias]) != nil)
        let farther = LyricMatchCandidate(trackName: "Example", artistName: "The Weeknd",
            albumName: "Another Collection", duration: 242, syncedLyrics: "[00:05]A", instrumental: false)
        assert(LyricMatching.select(title: "Example", artist: "Abel Tesfaye", albumName: "Another Album",
            duration: 240, from: [alias, farther])?.syncedLyrics == alias.syncedLyrics)
        print("LRC parsing and timeline tests passed")
        let partialData = Data(#"[{"trackName":"Example","artistName":"The Weeknd","albumName":null,"duration":null,"syncedLyrics":"[00:01]Unknown"},{"trackName":"Example","artistName":"The Weeknd","albumName":"Another Album","duration":240,"syncedLyrics":"[00:01]Valid"}]"#.utf8)
        let partial = try! JSONDecoder().decode([LyricMatchCandidate].self, from: partialData)
        assert(LyricMatching.select(title: "Example", artist: "Abel Tesfaye", albumName: "Another Album",
                                   duration: 240, from: partial)?.syncedLyrics == "[00:01]Valid")
        assert(LyricMatching.select(title: "Example", artist: "The Weeknd", albumName: "",
                                   duration: 240, from: [partial[0]]) == nil)
        print("Incomplete search record regression tests passed")
    }
}
