import Foundation

@main
struct AppleTTMLLyricsTests {
    static func main() {
        let source = #"<tt xmlns="http://www.w3.org/ns/ttml"><head><metadata>Ignore</metadata></head><body><div><p begin="00:01.500" end="00:03.000"><span begin="1.5s">Hello</span> <span begin="2s">world</span></p><p begin="3s" end="5000ms">Next<br/>line</p></div></body></tt>"#
        let cues = AppleTTMLLyrics.parse(source)
        assert(LRCLyrics.line(at: 1, in: cues) == nil)
        assert(LRCLyrics.line(at: 2, in: cues) == "Hello world")
        assert(LRCLyrics.line(at: 3, in: cues) == "Next line")
        assert(LRCLyrics.line(at: 5, in: cues) == nil)
        let overlapping = AppleTTMLLyrics.parse(#"<tt><body><div><p begin="1s" end="4s">First</p><p begin="3s" end="6s">Second</p></div></body></tt>"#)
        assert(LRCLyrics.line(at: 4.5, in: overlapping) == "Second")
        assert(LRCLyrics.line(at: 6, in: overlapping) == nil)
        assert(AppleTTMLLyrics.seconds("01:02:03.5") == 3723.5)
        assert(AppleTTMLLyrics.seconds("garbage") == nil)
        assert(AppleTTMLLyrics.parse("<tt><broken>").isEmpty)
        print("Apple TTML timing, span, boundary and invalid XML tests passed")
    }
}
