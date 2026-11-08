#if os(macOS) && CUETO_APPLE_MUSIC_LYRICS
import SwiftUI

struct AppleMusicConnectionGuide: View {
    @ObservedObject var probe: AppleMusicDirectProbe
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var previewing = false
    @State private var checkingConnection = false

    private var completed: Bool { step == 2 && (probe.isConnected || previewing) }

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 8) {
                stepLabel("登录", index: 0)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                stepLabel("信任", index: 1)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                stepLabel("完成", index: 2)
                Spacer()
                Menu {
#if DEBUG
                    Button("预览引导") {
                        previewing = true
                        checkingConnection = false
                        step = 0
                    }
#endif
                    Button(String(localized: "重新连接"), action: probe.openLoginPage)
                    Button(String(localized: "断开连接"), action: probe.disconnect)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel(String(localized: "管理 Apple Music 连接…"))
            }
            .padding(.top, 8)

            illustration
                .frame(height: 116)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(completed ? String(localized: "连接完成") : title)
                    .font(.system(size: 20, weight: .semibold))
                Text(completed ? String(localized: "关闭窗口，享受菜单栏歌词。") : instruction)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(height: 38)
            }

            if checkingConnection && !probe.isConnected {
                Text(String(localized: "请先在 Apple 页面完成登录，再继续。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(height: 30)
            } else {
                Color.clear.frame(height: 30).accessibilityHidden(true)
            }

            HStack {
                if previewing { Text("预览").font(.caption).foregroundStyle(.secondary) }
                if step > 0 && !completed {
                    Button(String(localized: "上一步")) {
                        checkingConnection = false
                        step -= 1
                    }
                    .disabled(probe.busy)
                }
                Spacer()

                Button(actionLabel, action: advance)
                    .buttonStyle(.borderedProminent)
                    .disabled(!previewing && step == 2 && !probe.isConnected)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420, height: 400)
        .onAppear {
            step = probe.isConnected ? 2 : 0
            checkingConnection = false
        }
        .onChange(of: probe.isConnected) { _, connected in
            guard !previewing else { return }
            if connected && step == 0 { step = 1 }
            if !connected { step = 0; checkingConnection = false }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: step)
    }

    private func stepLabel(_ title: LocalizedStringKey, index: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: index < step || completed ? "checkmark.circle.fill" : "\(index + 1).circle")
            Text(title)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(index == step || completed ? Color.accentColor : .secondary)
    }

    private var title: String {
        switch step {
        case 0: String(localized: "登录 Apple Music")
        case 1: String(localized: "信任这个浏览器")
        default: String(localized: "连接完成")
        }
    }

    private var instruction: String {
        switch step {
        case 0: String(localized: "在接下来打开的 Apple 页面中登录你的订阅账号。")
        case 1: String(localized: "Apple 询问是否信任此浏览器时，选择「信任」，以便保留登录。")
        default: String(localized: "关闭窗口，享受菜单栏歌词。")
        }
    }

    private var actionLabel: String {
        if completed { return String(localized: "完成") }
        switch step {
        case 0: return String(localized: "打开登录页")
        case 1: return String(localized: "已完成，继续")
        default: return String(localized: "完成")
        }
    }

    private func advance() {
        if previewing {
            if step < 2 { step += 1 }
            else { probe.closeGuide() }
            return
        }
        if completed { probe.closeGuide(); return }
        switch step {
        case 0:
            probe.openLoginPage()
            step = 1
        case 1:
            if probe.isConnected { step = 2 }
            else { checkingConnection = true; probe.openLoginPage() }
        default: probe.closeGuide()
        }
    }

    private var illustration: some View {
        AppleMusicGuideMotion(step: step)
            .id(step)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}
#endif
