import Foundation

@main
struct CosmosCrashRecoveryTests {
    static func main() {
        let now = ISO8601DateFormatter().date(from: "2026-11-10T16:55:13+08:00")!
        let event = CosmosExitEvent(processID: 321, launchedAt: now.addingTimeInterval(-60), exitedAt: now)
        let report: [String: Any] = [
            "pid": 321, "procLaunch": "2026-11-10 16:54:13.0000 +0800",
            "captureTime": "2026-11-10 16:55:13.5199 +0800",
            "bundleInfo": ["CFBundleIdentifier": "app.podcast.cosmos"],
            "termination": ["namespace": "RUNNINGBOARD", "code": 3_735_883_980]
        ]
        func data(_ report: [String: Any], header: Bool = true) -> Data {
            var value = header ? Data("{\"app_name\":\"Podcast\"}\n".utf8) : Data()
            value.append(try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]))
            return value
        }
        assert(CosmosCrashRecoveryPolicy.matches(data(report), event: event))
        assert(CosmosCrashRecoveryPolicy.matches(data(report, header: false), event: event))
        var changed = report
        changed["pid"] = 999
        assert(!CosmosCrashRecoveryPolicy.matches(data(changed), event: event))
        changed = report; changed["bundleInfo"] = ["CFBundleIdentifier": "com.apple.podcasts"]
        assert(!CosmosCrashRecoveryPolicy.matches(data(changed), event: event))
        changed = report; changed["termination"] = ["namespace": "SIGNAL", "code": 9]
        assert(!CosmosCrashRecoveryPolicy.matches(data(changed), event: event))
        changed = report; changed["termination"] = ["namespace": "RUNNINGBOARD", "code": 1]
        assert(!CosmosCrashRecoveryPolicy.matches(data(changed), event: event))
        changed = report; changed["captureTime"] = "2026-11-09 16:55:13.0000 +0800"
        assert(!CosmosCrashRecoveryPolicy.matches(data(changed), event: event))
        changed = report; changed["procLaunch"] = "2026-11-10 15:54:13.0000 +0800"
        assert(!CosmosCrashRecoveryPolicy.matches(data(changed), event: event))
        changed = report; changed.removeValue(forKey: "procLaunch")
        assert(!CosmosCrashRecoveryPolicy.matches(data(changed), event: event))
        assert(!CosmosCrashRecoveryPolicy.matches(Data("incomplete".utf8), event: event))
        assert(!CosmosCrashRecoveryPolicy.matches(data(report), event:
            CosmosExitEvent(processID: 321, launchedAt: event.launchedAt, exitedAt: now.addingTimeInterval(120))))

        var budget = CosmosRecoveryBudget()
        assert(budget.permits(at: now))
        budget.record(at: now)
        assert(!budget.permits(at: now.addingTimeInterval(119)))
        assert(budget.permits(at: now.addingTimeInterval(120)))
        budget.record(at: now.addingTimeInterval(120))
        budget.record(at: now.addingTimeInterval(240))
        assert(!budget.permits(at: now.addingTimeInterval(360)))
        assert(budget.permits(at: now.addingTimeInterval(1800)))
        assert(!budget.permits(at: now.addingTimeInterval(-1)))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // A normal exit or a not-yet-generated report must never trigger a launch.
        assert(CosmosCrashRecoveryMonitor.findReport(for: event, directory: directory) == .noMatch)
        let file = directory.appendingPathComponent("Podcast-test.ips")
        try! Data("incomplete".utf8).write(to: file)
        assert(CosmosCrashRecoveryMonitor.findReport(for: event, directory: directory) == .noMatch)
        try! data(report).write(to: file, options: .atomic)
        try! FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-60)], ofItemAtPath: file.path)
        assert(CosmosCrashRecoveryMonitor.findReport(for: event, directory: directory) == .noMatch)
        try! FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
        assert(CosmosCrashRecoveryMonitor.findReport(for: event, directory: directory) == .matched)
        // An unreadable/non-directory source fails closed instead of relaunching.
        assert(CosmosCrashRecoveryMonitor.findReport(for: event, directory: file) == .unavailable)
        print("Crash identity, timestamps, exact cause, malformed report and restart-budget tests passed")
    }
}
