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
        let timeline = [LyricCue(time: 10, text: "First"), LyricCue(time: 14, text: ""),
                        LyricCue(time: 20, text: "Second"), LyricCue(time: 25, text: ""),
                        LyricCue(time: 25.2, text: "Third"), LyricCue(time: 30, text: "")]
        assert(LRCLyrics.context(at: 0, in: timeline) == LyricContext(next: timeline[0]))
        assert(LRCLyrics.context(at: 10, in: timeline) == LyricContext(current: timeline[0], next: timeline[2]))
        assert(LRCLyrics.context(at: 16, in: timeline) == LyricContext(previous: timeline[0], next: timeline[2]))
        assert(LRCLyrics.context(at: 20, in: timeline) == LyricContext(previous: timeline[0], current: timeline[2], next: timeline[4]))
        assert(LRCLyrics.context(at: 25.1, in: timeline, bridgingGapsUpTo: 0.25).current == timeline[2])
        assert(LRCLyrics.context(at: 40, in: timeline) == LyricContext(previous: timeline[4]))
        assert(LRCLyrics.context(at: 2, in: duplicate).current?.text == "B")
        assert(LRCLyrics.context(at: .nan, in: timeline) == LyricContext())
        assert(LRCLyrics.context(at: 20, in: []).current == nil)
        for offset in [-0.5, 0, 0.5] {
            let target = LRCLyrics.seekPosition(for: timeline[2], in: timeline, timingOffset: offset, duration: 40)
            let roundedDownPosition = floor(target * 1000) / 1000
            assert(LRCLyrics.context(at: roundedDownPosition + offset, in: timeline).current == timeline[2])
        }
        let pauses = [LyricCue(time: 0, text: "First"), LyricCue(time: 5, text: ""),
                      LyricCue(time: 6.4, text: "Second"), LyricCue(time: 9, text: ""),
                      LyricCue(time: 11, text: "Third"), LyricCue(time: 14, text: ""),
                      LyricCue(time: 18, text: "Fourth")]
        assert(LRCLyrics.context(at: 5.8, in: pauses, bridgingGapsUpTo: 2).current == pauses[0])
        assert(LRCLyrics.context(at: 6.4, in: pauses, bridgingGapsUpTo: 2).current == pauses[2])
        assert(LRCLyrics.context(at: 10.9, in: pauses, bridgingGapsUpTo: 2).current == pauses[2])
        assert(LRCLyrics.context(at: 11, in: pauses, bridgingGapsUpTo: 2).current == pauses[4])
        assert(LRCLyrics.context(at: 15, in: pauses, bridgingGapsUpTo: 2).current == nil)
        assert(LRCLyrics.context(at: 18, in: pauses, bridgingGapsUpTo: 2).current == pauses[6])
        for position in [5.8, 6.4, 10.9, 11, 15, 18] {
            assert(LRCLyrics.context(at: position, in: pauses, bridgingGapsUpTo: 2).current?.text ==
                   LRCLyrics.line(at: position, in: pauses, bridgingGapsUpTo: 2))
        }
        var interlude = LyricInterludeState()
        let longGap = LRCLyrics.context(at: 15, in: pauses, bridgingGapsUpTo: 2)
        interlude.update(context: longGap, position: 15, duration: 30)
        assert(interlude.isVisible)
        interlude.update(context: longGap, position: 17.9, duration: 30)
        assert(interlude.isVisible)
        interlude.update(context: LRCLyrics.context(at: 18, in: pauses), position: 18, duration: 30)
        assert(!interlude.isVisible)
        interlude.update(context: longGap, position: 17.5, duration: 30)
        assert(!interlude.isVisible)
        interlude.update(context: LyricContext(next: LyricCue(time: 1, text: "Opening")), position: 0, duration: 30)
        assert(!interlude.isVisible)
        interlude.update(context: LyricContext(next: LyricCue(time: 5, text: "Opening")), position: 0, duration: 30)
        assert(interlude.isVisible)
        interlude.update(context: LyricContext(next: LyricCue(time: 5, text: "Opening")), position: 4.9, duration: 30)
        assert(interlude.isVisible)
        interlude.update(context: longGap, position: .nan, duration: 30)
        assert(!interlude.isVisible)
        let brief = [LyricCue(time: 1, text: "Short"), LyricCue(time: 1.01, text: "Next")]
        let briefTarget = LRCLyrics.seekPosition(for: brief[0], in: brief, timingOffset: 0, duration: 40)
        assert(briefTarget > 1 && briefTarget < 1.01)
        assert(LRCLyrics.seekPosition(for: timeline[0], in: timeline, timingOffset: 20, duration: 40) == 0)
        assert(LRCLyrics.seekPosition(for: timeline[2], in: timeline, timingOffset: -20, duration: 30) == 30)
        // The same corrected position drives panel and menu-bar highlighting,
        // including a backward seek and a positive (earlier display) offset.
        for position in [24.9, 25.1, 10.0, 14.0, 0, 19.5 + 0.5] {
            assert(LRCLyrics.context(at: position, in: timeline, bridgingGapsUpTo: 0.25).current?.text ==
                   LRCLyrics.line(at: position, in: timeline, bridgingGapsUpTo: 0.25))
        }
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
