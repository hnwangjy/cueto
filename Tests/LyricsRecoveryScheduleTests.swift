import Foundation

@main
struct LyricsRecoveryScheduleTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 1000)
        var schedule = LyricsRecoverySchedule()
        assert(!schedule.isDue(at: now))
        for delay: TimeInterval in [30, 60, 120, 300, 300] {
            schedule.failed(at: now)
            assert(!schedule.isDue(at: now.addingTimeInterval(delay - 1)))
            assert(schedule.isDue(at: now.addingTimeInterval(delay)))
        }
        schedule.connectionRecovered(at: now)
        assert(schedule.isDue(at: now))
        schedule.reset()
        assert(!schedule.isDue(at: now.addingTimeInterval(9999)))
        schedule.connectionRecovered(at: now)
        assert(!schedule.isDue(at: now))
        schedule.failed(at: now)
        assert(schedule.deadline == now.addingTimeInterval(30))
        schedule.failed(at: now, missing: true)
        assert(schedule.deadline == now.addingTimeInterval(300))
        print("Lyrics recovery backoff and wake/network recovery tests passed")
    }
}
