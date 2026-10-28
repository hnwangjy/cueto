import Foundation

struct LyricsRecoverySchedule {
    private(set) var deadline: Date?
    private var failures = 0

    mutating func failed(at now: Date, missing: Bool = false) {
        let delays: [TimeInterval] = [30, 60, 120, 300]
        deadline = now.addingTimeInterval(missing ? 300 : delays[min(failures, delays.count - 1)])
        failures += 1
    }

    mutating func reset() { deadline = nil; failures = 0 }
    mutating func connectionRecovered(at now: Date) {
        if deadline != nil { deadline = now }
    }
    func isDue(at now: Date) -> Bool { deadline.map { now >= $0 } ?? false }
}
