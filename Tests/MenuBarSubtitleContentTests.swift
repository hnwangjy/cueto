import Foundation

@main
struct MenuBarSubtitleContentTests {
    static func main() {
        func content(_ lyric: String?, _ title: String? = "Song", _ artist: String? = "Artist") -> MenuBarSubtitleContent {
            .make(lyric: lyric, title: title, artist: artist, sourceIdentifier: "music", sourceName: "Music")
        }
        let line = content("  Real lyric\n")
        assert(line.text == "Real lyric" && !line.isMetadata)
        let waiting = content(nil)
        assert(waiting.text == "Song · Artist" && waiting.isMetadata)
        assert(content(" \n ") == waiting)
        assert(content(nil, "Song", nil).text == "Song")
        assert(content(nil, nil, " Artist ").text == "Artist")
        assert(content(nil, "Same", " Same ").text == "Same")
        assert(content(nil, " ", nil).text == "♪ Music")
        assert(content(nil, nil, nil).isMetadata)
        assert(content("Song · Artist") != waiting)
        let otherSource = MenuBarSubtitleContent.make(lyric: "Real lyric", title: nil, artist: nil,
            sourceIdentifier: "cosmos", sourceName: "Cosmos")
        assert(otherSource != line)
        let now = Date(timeIntervalSince1970: 1000)
        var continuity = MenuBarSubtitleContinuity()
        let track: [String?] = ["music", "Song", "Artist"]
        assert(continuity.resolve(waiting, trackIdentity: track, at: now) == waiting)
        assert(continuity.resolve(line, trackIdentity: track, at: now) == line)
        assert(continuity.resolve(waiting, trackIdentity: track, at: now) == line)
        assert(continuity.resolve(waiting, trackIdentity: track, at: now.addingTimeInterval(0.3)) == line)
        let next = content("Next lyric")
        assert(continuity.resolve(next, trackIdentity: track, at: now.addingTimeInterval(0.4)) == next)
        assert(continuity.refreshAt == nil)
        assert(continuity.resolve(waiting, trackIdentity: track, at: now.addingTimeInterval(1)) == next)
        let gap = continuity.resolve(waiting, trackIdentity: track, at: now.addingTimeInterval(1.7))
        assert(gap?.text == "" && gap?.sourceIdentifier == "music")
        assert(continuity.resolve(waiting, trackIdentity: track, at: now.addingTimeInterval(1.8))?.text == "")
        assert(continuity.refreshAt == nil)
        _ = continuity.resolve(line, trackIdentity: track, at: now.addingTimeInterval(2))
        assert(continuity.resolve(waiting, trackIdentity: ["music", "New song", "Artist"], at: now.addingTimeInterval(2.1)) == waiting)
        assert(continuity.resolve(nil, trackIdentity: [], at: now.addingTimeInterval(3)) == nil)
        assert(continuity.refreshAt == nil)
        var openedDuringGap = MenuBarSubtitleContinuity()
        assert(openedDuringGap.resolve(waiting, trackIdentity: track, at: now, hasEnteredLyrics: true)?.text == "")
        assert(openedDuringGap.resolve(line, trackIdentity: track, at: now.addingTimeInterval(0.1)) == line)
        let scroll = SubtitleScrollPlan(travel: 240, offset: 0, availableTime: nil)
        assert(scroll.duration == 5 && scroll.offset(at: 0.7) == 0)
        assert(abs(scroll.offset(at: scroll.hold + 2.5) - 120) < 0.001)
        assert(scroll.offset(at: 100) == 240)
        let resumed = SubtitleScrollPlan(travel: 300, offset: scroll.offset(at: scroll.hold + 2.5), availableTime: nil)
        assert(resumed.start == 120 && resumed.hold == 0 && resumed.offset(at: 0) == 120)
        let paced = SubtitleScrollPlan(travel: 240, offset: 0, availableTime: 8)
        assert(paced.duration > scroll.duration && paced.total < 8)
        assert(SubtitleScrollPlan(travel: 240, offset: 0, availableTime: 1).duration == scroll.duration)
        assert(SubtitleScrollPlan(travel: 240, offset: 300, availableTime: 8).duration == 0)
        assert(SubtitleScrollPlan(travel: 240, offset: 0, availableTime: .nan).duration == scroll.duration)
        var sampled = line
        sampled.scrollTimeBudget = 10
        var laterSample = line
        laterSample.scrollTimeBudget = 9
        assert(sampled == laterSample)
        print("Lyric priority, metadata fallback, empty inputs and source identity tests passed")
    }
}
