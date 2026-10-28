#if os(macOS)
import AppKit
import Combine
import SwiftUI

/// An independent entry point that remains reachable when status items overflow.
@MainActor
final class NotchPanelController {
    static let preferenceKey = "openPanelAtNotch"
    private let playback: PlaybackController
    private let subtitles: CosmosSubtitleMonitor
    private let appleLyrics: AppleMusicLyricsMonitor
    private let onOpenSettings: () -> Void
    private var timer: AnyCancellable?
    private var panel: NotchPanel?
    private var enteredAt: TimeInterval?
    private var leftAt: TimeInterval?
    private var suppressed = false
    private var screenFrame: NSRect?
    private let expansion = NotchExpansionState()
    private var pendingClose: DispatchWorkItem?

    init(playback: PlaybackController, subtitles: CosmosSubtitleMonitor, appleLyrics: AppleMusicLyricsMonitor, onOpenSettings: @escaping () -> Void) {
        self.playback = playback
        self.subtitles = subtitles
        self.appleLyrics = appleLyrics
        self.onOpenSettings = onOpenSettings
        UserDefaults.standard.register(defaults: [Self.preferenceKey: true])
        // Sampling position needs no event interception or extra Accessibility permission.
        timer = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect().sink { [weak self] _ in self?.update() }
    }

    static func notchRect(on screen: NSScreen) -> NSRect? {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea,
              right.minX > left.maxX else { return nil }
        return NSRect(x: left.maxX, y: screen.frame.maxY - screen.safeAreaInsets.top,
                      width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
    }

    private func update() {
        guard UserDefaults.standard.bool(forKey: Self.preferenceKey) else {
            hide(animated: false)
            enteredAt = nil
            return
        }
        let point = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime
        let target = NSScreen.screens.first { screen in
            Self.notchRect(on: screen)?.insetBy(dx: -4, dy: -2).contains(point) == true
        }
        if let panel, panel.isVisible {
            guard let screen = NSScreen.screens.first(where: { $0.frame == screenFrame }),
                  let notch = Self.notchRect(on: screen) else { hide(animated: false); return }
            if let content = panel.contentView {
                let height = content.fittingSize.height
                if height > 0, abs(height - panel.frame.height) > 1 {
                    var frame = panel.frame
                    frame.origin.y = screen.frame.maxY - height
                    frame.size.height = height
                    panel.setFrame(frame, display: true)
                }
            }
            // Include the bridge from the notch to the panel, so entering it never dismisses it.
            if panel.frame.union(notch).insetBy(dx: -12, dy: -8).contains(point) {
                leftAt = nil
                if pendingClose != nil && !suppressed {
                    pendingClose?.cancel()
                    pendingClose = nil
                    expansion.setExpanded(true)
                }
            } else if let leftAt, now - leftAt >= 0.4 {
                hide()
            } else if leftAt == nil {
                leftAt = now
            }
            return
        }
        guard let target else {
            enteredAt = nil
            suppressed = false
            return
        }
        guard !suppressed else { return }
        if let enteredAt, now - enteredAt >= 0.05 {
            show(on: target)
        } else if enteredAt == nil {
            enteredAt = now
        }
    }

    private func show(on screen: NSScreen) {
        guard let notch = Self.notchRect(on: screen) else { return }
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.onDismiss = { [weak self] in self?.suppressed = true; self?.hide() }
        let root = NotchPlaybackView(playback: playback, subtitles: subtitles, appleLyrics: appleLyrics,
            onOpenSettings: { [weak self] in
                self?.suppressed = true
                self?.hide(animated: false)
                self?.onOpenSettings()
            }, onClose: { [weak self] in self?.suppressed = true; self?.hide() })
        let host = NSHostingView(rootView: NotchExpansionView(
            state: expansion, notchSize: notch.size, content: root
        ).environment(\.controlActiveState, .active))
        let size = host.fittingSize
        panel.contentView = host
        panel.setFrame(NSRect(x: min(max(notch.midX - size.width / 2, screen.frame.minX + 8),
                                      screen.frame.maxX - size.width - 8),
                              y: screen.frame.maxY - size.height, width: size.width, height: size.height), display: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        screenFrame = screen.frame
        self.panel = panel
        leftAt = nil
        expansion.expanded = false
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel, self.panel === panel else { return }
            self.expansion.setExpanded(true)
        }
    }

    private func hide(animated: Bool = true) {
        guard panel != nil else { return }
        if animated {
            guard pendingClose == nil else { return }
            expansion.setExpanded(false)
            let task = DispatchWorkItem { [weak self] in self?.hide(animated: false) }
            pendingClose = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
            return
        }
        pendingClose?.cancel()
        pendingClose = nil
        panel?.orderOut(nil)
        panel = nil
        enteredAt = nil
        leftAt = nil
        screenFrame = nil
    }
}

@MainActor
private final class NotchExpansionState: ObservableObject {
    @Published var expanded = false

    func setExpanded(_ value: Bool) {
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduced ? .easeOut(duration: 0.12) :
            (value ? .spring(response: 0.42, dampingFraction: 0.68) : .easeOut(duration: 0.18))) {
            expanded = value
        }
    }
}

private struct NotchExpansionView<Content: View>: View {
    @ObservedObject var state: NotchExpansionState
    let notchSize: CGSize
    let content: Content
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchSize.height + 10)
            content
                .opacity(state.expanded ? 1 : 0)
                .offset(y: reducedMotion || state.expanded ? 0 : -10)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 32)
        .background {
            NotchGlassMaterial()
                .overlay(Color.black.opacity(0.1))
        }
        .mask(NotchRevealShape(progress: reducedMotion ? 1 : (state.expanded ? 1 : 0), notchSize: notchSize))
        .opacity(reducedMotion && !state.expanded ? 0 : 1)
        .environment(\.colorScheme, .dark)
        .fixedSize(horizontal: true, vertical: true)
    }
}

private struct NotchGlassMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// The top edge stays attached to the camera housing while the lower edge unfolds.
private struct NotchRevealShape: Shape {
    var progress: CGFloat
    let notchSize: CGSize
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let value = min(max(progress, 0), 1.08)
        let width = notchSize.width + (rect.width - 24 - notchSize.width) * value
        let height = notchSize.height + (rect.height - 32 - notchSize.height) * value
        let body = CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: height)
        let topRadius = 16 * min(value, 1)
        return UnevenRoundedRectangle(topLeadingRadius: topRadius, bottomLeadingRadius: 14 + 6 * value,
                                      bottomTrailingRadius: 14 + 6 * value, topTrailingRadius: topRadius)
            .path(in: body)
    }
}

private final class NotchPanel: NSPanel {
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}

private struct NotchPlaybackView: View {
    @ObservedObject var playback: PlaybackController
    @ObservedObject var subtitles: CosmosSubtitleMonitor
    @ObservedObject var appleLyrics: AppleMusicLyricsMonitor
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Cueto", systemImage: "waveform.mid").font(.headline)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("收起面板")
            }.padding(.horizontal, 16).padding(.top, 14)
            if playback.hasActiveSession {
                HStack(spacing: 26) {
                    Button(action: playback.goBackward) { Image(systemName: "backward.end.fill") }
                        .help(playback.backwardControlLabel)
                    Button(action: playback.playPause) { Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill") }
                        .help(playback.isPlaying ? "暂停" : "播放")
                    Button(action: playback.goForward) { Image(systemName: "forward.end.fill") }
                        .help(playback.forwardControlLabel)
                }
                .font(.system(size: 19)).buttonStyle(.borderless).padding(.top, 16)
                NowPlayingPopover(playback: playback, subtitles: subtitles, appleLyrics: appleLyrics, onOpenCueto: onOpenSettings,
                                  onQuit: { NSApplication.shared.terminate(nil) })
            } else {
                IdlePopover(playback: playback, onOpenCueto: onOpenSettings,
                            onQuit: { NSApplication.shared.terminate(nil) })
            }
        }
        .frame(width: 350)
        .fixedSize(horizontal: false, vertical: true)
    }
}
#endif
