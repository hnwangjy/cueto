import Foundation

nonisolated enum SubtitleScrollSpeed: String, CaseIterable {
    case slow, normal, fast

    var title: String {
        switch self {
        case .slow: return String(localized: "慢")
        case .normal: return String(localized: "标准")
        case .fast: return String(localized: "快")
        }
    }

    var multiplier: Double {
        switch self {
        case .slow: return 0.75
        case .normal: return 1
        case .fast: return 1.4
        }
    }
}

nonisolated enum SubtitleScrollStyle {
    case music, podcast
}

nonisolated struct SubtitleScrollPlan {
    let start: Double
    let end: Double
    let hold: TimeInterval
    let duration: TimeInterval
    var total: TimeInterval { hold + duration }

    init(travel: Double, offset: Double, availableTime: TimeInterval?,
         style: SubtitleScrollStyle = .music, speed: SubtitleScrollSpeed = .normal) {
        end = travel.isFinite ? max(0, travel) : 0
        start = offset.isFinite ? min(end, max(0, offset)) : 0
        let remaining = end - start
        hold = remaining > 0 && start == 0 ? 0.8 : 0
        let pointsPerSecond = (style == .podcast ? 72.0 : 48.0) * speed.multiplier
        let normal = remaining / pointsPerSecond
        let timed: TimeInterval
        if let availableTime, availableTime.isFinite {
            // Use reliable cue timing without forcing either frantic movement
            // or an unreadably slow crawl. Reserve a brief pause on the last words.
            timed = min(max(0, availableTime - hold - 0.55), remaining / 26)
        } else {
            timed = 0
        }
        duration = remaining > 0 ? max(0.25, max(normal, timed / speed.multiplier)) : 0
    }

    func offset(at elapsed: TimeInterval) -> Double {
        guard elapsed.isFinite else { return start }
        guard duration > 0 else { return end }
        let progress = min(1, max(0, (elapsed - hold) / duration))
        return start + (end - start) * progress
    }
}
