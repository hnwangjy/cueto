import Foundation
import CoreGraphics

@main
struct StatusBarHitRegionsTests {
    static func main() {
        // Short names, long names, and the extra source-count badge all resize
        // the left area. A click on a control must never turn into a source click.
        for width: CGFloat in [174, 210, 246] {
            for height: CGFloat in [22, 24, 32] {
                let bounds = CGRect(x: 0, y: 0, width: width, height: height)
                let backward = CGRect(x: width - 80, y: (height - 18) / 2, width: 25, height: 18)
                let play = backward.offsetBy(dx: 26, dy: 0)
                let forward = play.offsetBy(dx: 26, dy: 0)
                func hit(_ x: CGFloat, _ y: CGFloat, idle: Bool = false) -> StatusBarClickTarget? {
                    StatusBarHitRegions.target(at: CGPoint(x: x, y: y), in: bounds, idle: idle,
                                               backward: backward, playPause: play, forward: forward)
                }
                for y in [CGFloat(0.1), height / 2, height - 0.1] {
                    assert(hit(15, y) == .source)
                    assert(hit(backward.midX, y) == .backward)
                    assert(hit(play.midX, y) == .playPause)
                    assert(hit(forward.midX, y) == .forward)
                    assert(hit(play.midX, y, idle: true) == .source)
                }
                assert(hit(-1, 10) == nil)
                assert(hit(width + 1, 10) == nil)
                assert(hit(play.midX, height + 1) == nil)
                assert(hit((backward.maxX + play.minX) / 2, 10) == .playPause)
                assert(hit((play.maxX + forward.minX) / 2, 10) == .forward)
            }
        }
        print("Menu-bar source/control hit regions, full-height clicks, resize and boundaries passed")
    }
}
