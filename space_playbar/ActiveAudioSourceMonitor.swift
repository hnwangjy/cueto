#if os(macOS)
import AppKit
import Combine
import CoreAudio

struct ActiveAudioSource: Identifiable, Equatable {
    let processID: pid_t
    let bundleIdentifier: String
    let applicationName: String

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

    private var refreshTimer: AnyCancellable?

    init() {
        refresh()
        refreshTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        let discovered = Self.runningOutputSources()
        if discovered != sources {
            sources = discovered
        }
    }

    private static func runningOutputSources() -> [ActiveAudioSource] {
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
        for processObject in processObjects where isRunningOutput(processObject) {
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
            sourcesByBundleIdentifier[bundleIdentifier] = ActiveAudioSource(
                processID: processID,
                bundleIdentifier: bundleIdentifier,
                applicationName: applicationName
            )
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
