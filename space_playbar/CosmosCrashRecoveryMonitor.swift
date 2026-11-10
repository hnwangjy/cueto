#if os(macOS)
import AppKit
import Combine

@MainActor
final class CosmosCrashRecoveryMonitor: ObservableObject {
    @Published var isEnabled = UserDefaults.standard.bool(forKey: "recoverCosmosAfterKnownCrash") {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "recoverCosmosAfterKnownCrash")
            pendingRecovery?.cancel()
            statusMessage = nil
            if isEnabled { checkReportAccess() }
        }
    }
    @Published private(set) var statusMessage: String?
    private var observations = Set<AnyCancellable>()
    private var pendingRecovery: Task<Void, Never>?
    private var shuttingDown = false
    private var budget = CosmosRecoveryBudget(attempts:
        (UserDefaults.standard.array(forKey: "cosmosRecoveryAttempts") as? [Double] ?? [])
            .filter(\.isFinite).map { Date(timeIntervalSince1970: $0) })

    init() {
        let notifications = NSWorkspace.shared.notificationCenter
        notifications.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == CosmosCrashRecoveryPolicy.bundleIdentifier else { return }
                self?.check(CosmosExitEvent(processID: app.processIdentifier,
                                           launchedAt: app.launchDate, exitedAt: Date()))
            }
            .store(in: &observations)
        notifications.publisher(for: NSWorkspace.willPowerOffNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.shuttingDown = true
                self?.pendingRecovery?.cancel()
            }
            .store(in: &observations)
        notifications.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == CosmosCrashRecoveryPolicy.bundleIdentifier else { return }
                self?.pendingRecovery?.cancel()
            }
            .store(in: &observations)
        if isEnabled { checkReportAccess() }
    }

    private func checkReportAccess() {
        pendingRecovery = Task { [weak self] in
            let available = await Task.detached(priority: .utility) {
                do {
                    _ = try FileManager.default.contentsOfDirectory(at: Self.reportDirectory,
                        includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                    return true
                } catch CocoaError.fileReadNoSuchFile {
                    return true
                } catch { return false }
            }.value
            guard !Task.isCancelled, let self, self.isEnabled else { return }
            if !available {
                self.statusMessage = String(localized: "无法读取系统诊断报告，自动恢复暂不可用。")
            }
        }
    }

    private var cosmosIsRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: CosmosCrashRecoveryPolicy.bundleIdentifier)
            .contains { !$0.isTerminated }
    }

    private func check(_ event: CosmosExitEvent) {
        guard isEnabled, !shuttingDown else { return }
        pendingRecovery?.cancel()
        statusMessage = nil
        pendingRecovery = Task { [weak self] in
            // Reports may arrive after the exit notification. Stop after one minute.
            for delay in [2, 3, 5, 10, 15, 25] {
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard let self, !Task.isCancelled, self.isEnabled,
                      !self.shuttingDown, !self.cosmosIsRunning else { return }
                let result = await Task.detached(priority: .utility) { Self.findReport(for: event) }.value
                guard !Task.isCancelled, self.isEnabled, !self.shuttingDown, !self.cosmosIsRunning else { return }
                switch result {
                case .noMatch: continue
                case .unavailable:
                    self.statusMessage = String(localized: "无法读取系统诊断报告，自动恢复暂不可用。")
                    return
                case .matched:
                    self.reopen()
                    return
                }
            }
        }
    }

    private func reopen() {
        let now = Date()
        guard budget.permits(at: now) else {
            statusMessage = String(localized: "小宇宙连续异常退出，已暂停本次自动恢复。")
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: CosmosCrashRecoveryPolicy.bundleIdentifier) else {
            statusMessage = String(localized: "找不到小宇宙，请手动打开。")
            return
        }
        budget.record(at: now)
        UserDefaults.standard.set(budget.attempts.map(\.timeIntervalSince1970), forKey: "cosmosRecoveryAttempts")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        // No play/resume command is sent; Music.app's global media route is untouched.
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self, self.isEnabled else { return }
                self.statusMessage = error == nil ? String(localized: "已重新打开小宇宙") :
                    String(localized: "未能重新打开小宇宙，请手动打开。")
            }
        }
    }

    nonisolated enum ReportResult: Equatable, Sendable { case matched, noMatch, unavailable }

    nonisolated private static var reportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    }

    nonisolated static func findReport(for event: CosmosExitEvent, directory: URL? = nil) -> ReportResult {
        let directory = directory ?? reportDirectory
        do {
            let files = try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles])
            let candidates = files.compactMap { url -> (URL, Date)? in
                guard url.pathExtension == "ips",
                      url.lastPathComponent.hasPrefix("Podcast-") || url.lastPathComponent.hasPrefix("小宇宙-"),
                      let info = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
                      info.isRegularFile == true, let modified = info.contentModificationDate,
                      modified >= event.exitedAt.addingTimeInterval(-30),
                      let size = info.fileSize, size <= 16 * 1_024 * 1_024 else { return nil }
                return (url, modified)
            }.sorted { $0.1 > $1.1 }.prefix(32)
            for (url, _) in candidates {
                do {
                    let data = try Data(contentsOf: url)
                    if CosmosCrashRecoveryPolicy.matches(data, event: event) { return .matched }
                } catch CocoaError.fileReadNoSuchFile {
                    continue
                } catch { return .unavailable }
            }
            return .noMatch
        } catch CocoaError.fileReadNoSuchFile {
            return .noMatch
        } catch {
            return .unavailable
        }
    }
}
#endif
