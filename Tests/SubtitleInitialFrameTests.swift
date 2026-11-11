import AppKit

@main
struct SubtitleInitialFrameTests {
    @MainActor static func main() {
        let view = SubtitleStatusView(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        let line = "This is a long lyric whose opening words must remain visible before scrolling begins."
        func textLayer() -> CALayer {
            view.layer!.sublayers!.last!.sublayers!.first!
        }
        view.show(.make(lyric: line, title: nil, artist: nil, sourceIdentifier: "test", sourceName: "Test"))
        // No attached window/presentation tree: the model itself must show the
        // opening, not the final translation hidden by an animation elsewhere.
        assert(textLayer().transform.m41 == 0)
        view.setFrameSize(NSSize(width: 120, height: 24))
        assert(textLayer().transform.m41 == 0)
        view.show(.make(lyric: line + " More words.", title: nil, artist: nil, sourceIdentifier: "test", sourceName: "Test"))
        assert(textLayer().transform.m41 == 0)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        var podcast = MenuBarSubtitleContent.make(lyric: line, title: nil, artist: nil,
            sourceIdentifier: "cosmos", sourceName: "Cosmos", scrollStyle: .podcast)
        view.show(podcast)
        RunLoop.main.run(until: Date().addingTimeInterval(0.95))
        let beforeSpeedChange = textLayer().transform.m41
        assert(beforeSpeedChange < 0)
        podcast.scrollSpeed = .fast
        view.show(podcast)
        assert(textLayer().transform.m41 <= beforeSpeedChange)
        let beforeResize = textLayer().transform.m41
        view.setFrameSize(NSSize(width: 100, height: 24))
        assert(textLayer().transform.m41 <= beforeResize)
        window.contentView = nil
        print("Sentence openings and in-progress positions survive width and speed changes")
    }
}
