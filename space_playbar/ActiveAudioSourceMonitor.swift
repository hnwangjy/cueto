#if os(macOS)
import AppKit
import Combine
import CoreAudio

struct ActiveAudioSource: Identifiable, Equatable {
    let processID: pid_t
    let bundleIdentifier: String
    let applicationName: String
    let isRunningOutput: Bool

    init(
        processID: pid_t,
        bundleIdentifier: String,
        applicationName: String,
        isRunningOutput: Bool = true
    ) {
        self.processID = processID
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.isRunningOutput = isRunningOutput
    }

    var id: String { bundleIdentifier }

    var icon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}

@MainActor
final class ActiveAudioSourceMonitor: ObservableObject {
    @Published private(set) var sources: [ActiveAudioSource] = []
    @Published private(set) var processSources: [ActiveAudioSource] = []

    private var refreshTimer: AnyCancellable?
    private var observedSources: [String: ActiveAudioSource] = [:]

    init() {
        refresh()
        refreshTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        let discovered = Self.audioProcessSources()
        for source in discovered {
            observedSources[source.bundleIdentifier] = source
        }
        observedSources = observedSources.filter { _, source in
            NSRunningApplication(processIdentifier: source.processID)?.bundleIdentifier == source.bundleIdentifier
        }

        let active = discovered.filter(\.isRunningOutput)
        if active != sources {
            sources = active
        }
        let available = observedSources.values.map { source in
            discovered.first(where: { $0.bundleIdentifier == source.bundleIdentifier })
                ?? ActiveAudioSource(
                    processID: source.processID,
                    bundleIdentifier: source.bundleIdentifier,
                    applicationName: source.applicationName,
                    isRunningOutput: false
                )
        }.sorted {
            if $0.isRunningOutput != $1.isRunningOutput { return $0.isRunningOutput }
            return $0.applicationName.localizedStandardCompare($1.applicationName) == .orderedAscending
        }
        if available != processSources {
            processSources = available
        }
    }

    func rememberMediaSource(processID: pid_t, bundleIdentifier: String, applicationName: String) {
        let resolvedProcessID = processID > 0 ? processID : NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleIdentifier })?.processIdentifier ?? 0
        guard resolvedProcessID > 0,
              NSRunningApplication(processIdentifier: resolvedProcessID)?.bundleIdentifier == bundleIdentifier else {
            return
        }
        if let existing = observedSources[bundleIdentifier],
           existing.processID == resolvedProcessID,
           existing.applicationName == applicationName {
            return
        }
        observedSources[bundleIdentifier] = ActiveAudioSource(
            processID: resolvedProcessID,
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            isRunningOutput: false
        )
        refresh()
    }

    private static func audioProcessSources() -> [ActiveAudioSource] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &byteCount
        ) == noErr, byteCount > 0 else {
            return []
        }

        var processObjects = Array(
            repeating: AudioObjectID(kAudioObjectUnknown),
            count: Int(byteCount) / MemoryLayout<AudioObjectID>.size
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &byteCount,
            &processObjects
        ) == noErr else {
            return []
        }

        var sourcesByBundleIdentifier: [String: ActiveAudioSource] = [:]
        for processObject in processObjects {
            guard let processID = property(processObject, selector: kAudioProcessPropertyPID, as: pid_t.self),
                  processID != ProcessInfo.processInfo.processIdentifier,
                  let runningApplication = NSRunningApplication(processIdentifier: processID),
                  runningApplication.activationPolicy == .regular,
                  let bundleIdentifier = runningApplication.bundleIdentifier,
                  !bundleIdentifier.isEmpty else {
                continue
            }

            let applicationName = runningApplication.localizedName
                ?? applicationDisplayName(bundleIdentifier: bundleIdentifier)
            let source = ActiveAudioSource(
                processID: processID,
                bundleIdentifier: bundleIdentifier,
                applicationName: applicationName,
                isRunningOutput: isRunningOutput(processObject)
            )
            if source.isRunningOutput || sourcesByBundleIdentifier[bundleIdentifier] == nil {
                sourcesByBundleIdentifier[bundleIdentifier] = source
            }
        }

        return sourcesByBundleIdentifier.values.sorted {
            $0.applicationName.localizedStandardCompare($1.applicationName) == .orderedAscending
        }
    }

    private static func isRunningOutput(_ objectID: AudioObjectID) -> Bool {
        property(objectID, selector: kAudioProcessPropertyIsRunningOutput, as: UInt32.self) == 1
    }

    private static func property<T>(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        as type: T.Type
    ) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, value) == noErr else {
            return nil
        }
        return value.pointee
    }

    private static func applicationDisplayName(bundleIdentifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return bundleIdentifier
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }
}
#endif
