import Foundation

nonisolated struct CosmosExitEvent: Sendable {
    let processID: Int32
    let launchedAt: Date?
    let exitedAt: Date
}

nonisolated enum CosmosCrashRecoveryPolicy {
    static let bundleIdentifier = "app.podcast.cosmos"

    private struct Report: Decodable {
        struct BundleInfo: Decodable { let CFBundleIdentifier: String? }
        struct Termination: Decodable { let namespace: String; let code: UInt64 }
        let pid: Int32
        let procLaunch: String?
        let captureTime: String
        let bundleInfo: BundleInfo
        let termination: Termination
    }

    static func matches(_ data: Data, event: CosmosExitEvent) -> Bool {
        guard event.processID > 0 else { return false }
        let decoder = JSONDecoder()
        // Modern .ips files contain a one-line metadata object before the report.
        let report = (try? decoder.decode(Report.self, from: data)) ?? data.firstIndex(of: 10).flatMap {
            try? decoder.decode(Report.self, from: Data(data[data.index(after: $0)...]))
        }
        guard let report,
              report.bundleInfo.CFBundleIdentifier == bundleIdentifier,
              report.pid == event.processID,
              report.termination.namespace == "RUNNINGBOARD",
              report.termination.code == 0xDEAD10CC,
              let capturedAt = date(report.captureTime),
              abs(capturedAt.timeIntervalSince(event.exitedAt)) <= 30 else { return false }
        if let launchedAt = event.launchedAt {
            guard let value = report.procLaunch, let reportLaunch = date(value),
                  abs(reportLaunch.timeIntervalSince(launchedAt)) <= 3 else { return false }
        }
        return true
    }

    private static func date(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSS Z"
        formatter.isLenient = false
        return formatter.date(from: value)
    }
}

nonisolated struct CosmosRecoveryBudget {
    var attempts: [Date] = []

    func permits(at now: Date) -> Bool {
        let recent = attempts.filter { now.timeIntervalSince($0) < 30 * 60 }
        return recent.count < 3 && !recent.contains { now.timeIntervalSince($0) < 120 }
    }

    mutating func record(at now: Date) {
        attempts = attempts.filter { now.timeIntervalSince($0) < 30 * 60 }
        attempts.append(now)
    }
}
