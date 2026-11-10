import Foundation

nonisolated struct SubtitleScrollPlan {
    let start: Double
    let end: Double
    let hold: TimeInterval
    let duration: TimeInterval
    var total: TimeInterval { hold + duration }

    init(travel: Double, offset: Double, availableTime: TimeInterval?) {
        end = travel.isFinite ? max(0, travel) : 0
        start = offset.isFinite ? min(end, max(0, offset)) : 0
        let remaining = end - start
        hold = remaining > 0 && start == 0 ? 0.8 : 0
        let normal = remaining / 48
        let timed: TimeInterval
        if let availableTime, availableTime.isFinite {
            // Use reliable cue timing without forcing either frantic movement
            // or an unreadably slow crawl. Reserve a brief pause on the last words.
            timed = min(max(0, availableTime - hold - 0.55), remaining / 26)
        } else {
            timed = 0
        }
        duration = remaining > 0 ? max(0.25, max(normal, timed)) : 0
    }

    func offset(at elapsed: TimeInterval) -> Double {
        guard elapsed.isFinite else { return start }
        guard duration > 0 else { return end }
        let progress = min(1, max(0, (elapsed - hold) / duration))
        return start + (end - start) * progress
    }
}
