#if os(macOS)
import AppKit
import AudioToolbox
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class MenuBarVolumeController {
    static let hapticsPreferenceKey = "menuBarVolumeHapticsEnabled"

    var isSuspended = false {
        didSet {
            if isSuspended { dismiss() }
        }
    }

    private weak var anchor: NSView?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var reveal: DispatchWorkItem?
    private var panel: NSPanel?
    private var panelDestination: NSRect?
    private var retractionID: UUID?
    private var hovered = false
    private let display = VolumeDisplay()
    private static let panelSize = NSSize(width: 198, height: 44)

    init(anchor: NSView) {
        self.anchor = anchor
        let events: NSEvent.EventTypeMask = [.mouseMoved, .scrollWheel]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event) == true ? nil : event
            }
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { _ = self?.handle(event) }
        }
    }

    func stop() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        dismiss()
    }

    func dismiss(animated: Bool = false) {
        hovered = false
        reveal?.cancel()
        reveal = nil
        retractionID = nil

        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let panel, panel.isVisible, let destination = panelDestination else {
            panelDestination = nil
            panel?.orderOut(nil)
            return
        }

        let id = UUID()
        retractionID = id
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.13
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
            panel.animator().setFrame(Self.collapsedFrame(for: destination), display: false)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            guard let self, self.retractionID == id else { return }
            self.retractionID = nil
            self.panelDestination = nil
            panel?.orderOut(nil)
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard !isSuspended else { return false }
        guard let rect = anchorRect(), rect.contains(NSEvent.mouseLocation) else {
            if hovered { dismiss(animated: true) }
            return false
        }
        if !hovered {
            hovered = true
            if retractionID != nil, let output = SystemOutputVolume.current() {
                show(output.value)
            } else {
                if panel == nil { _ = makePanel(size: Self.panelSize) }
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.hovered, self.anchorRect()?.contains(NSEvent.mouseLocation) == true,
                          let output = SystemOutputVolume.current() else { return }
                    self.show(output.value)
                }
                reveal = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
            }
        }
        guard event.type == .scrollWheel,
              abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
              let output = SystemOutputVolume.current() else { return false }
        guard event.momentumPhase.isEmpty else { return true }
        // Volume follows physical input direction, independent of Natural Scrolling.
        let verticalDelta = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
        let delta: Float
        if event.hasPreciseScrollingDeltas {
            delta = Float(verticalDelta) * 0.003
        } else {
            delta = verticalDelta > 0 ? 0.04 : -0.04
        }
        let next = min(max(output.value + delta, 0), 1)
        if next != output.value, !output.set(next) { return false }
        reveal?.cancel()
        reveal = nil
        let volume = SystemOutputVolume.current()?.value ?? next
        if event.hasPreciseScrollingDeltas, volume != output.value,
           Int(volume * 20) != Int(output.value * 20) || volume == 0,
           UserDefaults.standard.object(forKey: Self.hapticsPreferenceKey) as? Bool ?? true {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        show(volume)
        return true
    }

    private func anchorRect() -> NSRect? {
        guard let anchor, !anchor.isHiddenOrHasHiddenAncestor,
              let window = anchor.window, window.isVisible, !anchor.visibleRect.isEmpty else { return nil }
        return window.convertToScreen(anchor.convert(anchor.visibleRect, to: nil))
    }

    private static func collapsedFrame(for frame: NSRect) -> NSRect {
        let scale: CGFloat = 0.965
        let width = frame.width * scale
        let height = frame.height * scale
        return NSRect(x: frame.midX - width / 2, y: frame.maxY + 3 - height, width: width, height: height)
    }

    private func show(_ volume: Float) {
        guard let rect = anchorRect(), let screen = anchor?.window?.screen else { return }
        display.value = Double(volume)
        let size = Self.panelSize
        let window = panel ?? makePanel(size: size)
        let x = min(max(rect.midX - size.width / 2, screen.visibleFrame.minX + 4),
                    screen.visibleFrame.maxX - size.width - 4)
        let destination = NSRect(x: x, y: rect.minY - size.height - 4, width: size.width, height: size.height)
        let isRetracting = retractionID != nil
        retractionID = nil
        // Wheel updates should never interrupt or restart the reveal.
        if window.isVisible && !isRetracting {
            if panelDestination != destination {
                panelDestination = destination
                window.setFrame(destination, display: false)
            }
            return
        }
        panelDestination = destination

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            window.setFrame(destination, display: false)
            window.alphaValue = 1
            window.orderFrontRegardless()
            return
        }

        if !window.isVisible {
            window.alphaValue = 0
            window.setFrame(Self.collapsedFrame(for: destination), display: false)
            window.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.17
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.7, 0.26, 1)
            window.animator().setFrame(destination, display: false)
            window.animator().alphaValue = 1
        }
    }

    private func makePanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        let material = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        // Behind-window blur uses its own mask, independent of the view's layer.
        let radius = VolumeIndicator.cornerRadius
        material.maskImage = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }

        let content = NSHostingView(rootView: VolumeIndicator(display: display))
        content.frame = material.bounds
        content.autoresizingMask = [.width, .height]
        material.addSubview(content)
        panel.contentView = material
        material.layoutSubtreeIfNeeded()
        _ = material.maskImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        self.panel = panel
        return panel
    }
}

private final class VolumeDisplay: ObservableObject {
    @Published var value = 0.0
}

private struct VolumeIndicator: View {
    static let cornerRadius: CGFloat = 14
    @ObservedObject var display: VolumeDisplay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: display.value == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 19)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.13))
                    Capsule().fill(.primary.opacity(0.82))
                        .frame(width: geometry.size.width * display.value)
                }
            }
            .frame(height: 6)
            Text(display.value.formatted(.percent.precision(.fractionLength(0))))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .circular)
                .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "系统音量"))
        .accessibilityValue(display.value.formatted(.percent.precision(.fractionLength(0))))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: display.value)
    }
}

private struct SystemOutputVolume {
    let device: AudioDeviceID
    let address: AudioObjectPropertyAddress
    let value: Float32

    static func current() -> Self? {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var property = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }

        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyVolumeScalar] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain)
            var settable: DarwinBoolean = false
            guard AudioObjectHasProperty(device, &address),
                  AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
                  settable.boolValue else { continue }
            var volume: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr, volume.isFinite {
                return Self(device: device, address: address, value: min(max(volume, 0), 1))
            }
        }
        return nil
    }

    func set(_ volume: Float32) -> Bool {
        var address = address
        var volume = volume
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume) == noErr
    }
}
#endif
