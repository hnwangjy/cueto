#if os(macOS)
import AppKit
import Combine
import ServiceManagement
import Sparkle
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ExcludedAudioApps: ObservableObject {
    @Published private(set) var bundleIdentifiers: Set<String>
    @Published private(set) var applicationNames: [String: String]

    private let identifiersKey = "excludedAudioAppBundleIdentifiers"
    private let namesKey = "excludedAudioAppNames"

    init() {
        bundleIdentifiers = Set(UserDefaults.standard.stringArray(forKey: identifiersKey) ?? [])
        applicationNames = UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String] ?? [:]
    }

    func setExcluded(_ excluded: Bool, identifier: String, name: String) {
        if excluded {
            applicationNames[identifier] = name
            bundleIdentifiers.insert(identifier)
        } else {
            bundleIdentifiers.remove(identifier)
            applicationNames.removeValue(forKey: identifier)
        }
        UserDefaults.standard.set(bundleIdentifiers.sorted(), forKey: identifiersKey)
        UserDefaults.standard.set(applicationNames, forKey: namesKey)
    }
}

@MainActor
final class CuetoSettingsModel: ObservableObject {
    @Published private(set) var launchAtLogin = false
    @Published private(set) var requiresLoginItemApproval = false
    @Published private(set) var canCheckForUpdates = false
    @Published var errorMessage: String?

    private let updater: SPUUpdater

    private let onManualUpdateCheck: () -> Void

    init(updater: SPUUpdater, onManualUpdateCheck: @escaping () -> Void) {
        self.updater = updater
        self.onManualUpdateCheck = onManualUpdateCheck
        refresh()
    }

    var automaticallyChecksForUpdates: Bool {
        updater.automaticallyChecksForUpdates
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        requiresLoginItemApproval = status == .requiresApproval
        canCheckForUpdates = updater.canCheckForUpdates
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = String(localized: "无法更改开机启动设置：\(error.localizedDescription)")
        }
        refresh()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updater.automaticallyChecksForUpdates = enabled
        objectWillChange.send()
    }

    func checkForUpdates() {
        guard updater.canCheckForUpdates else { return }
        onManualUpdateCheck()
        updater.checkForUpdates()
    }

    func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}

struct CuetoSettingsView: View {
    @AppStorage("openPanelAtNotch") private var openPanelAtNotch = true
    @ObservedObject var model: CuetoSettingsModel
    @ObservedObject var excludedApps: ExcludedAudioApps
    @ObservedObject var subtitles: CosmosSubtitleMonitor
    @ObservedObject var appleLyrics: AppleMusicLyricsMonitor
    @ObservedObject var cosmosRecovery: CosmosCrashRecoveryMonitor
    @State private var runningApps: [NSRunningApplication] = []

    private var appChoices: [(identifier: String, name: String)] {
        var names = excludedApps.applicationNames
        for app in runningApps where app.activationPolicy == .regular {
            if let identifier = app.bundleIdentifier, identifier != Bundle.main.bundleIdentifier {
                names[identifier] = app.localizedName ?? identifier
            }
        }
        return names.map { ($0.key, $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return String(localized: "版本 \(version)（\(build)）")
    }

    private enum Section: String, CaseIterable, Identifiable {
        case general, lyrics, hiddenApps, experiments
        var id: Self { self }
        var title: String {
            switch self {
            case .general: String(localized: "通用")
            case .lyrics: String(localized: "歌词")
            case .hiddenApps: String(localized: "隐藏应用")
            case .experiments: String(localized: "实验功能")
            }
        }
        var icon: String {
            switch self {
            case .general: "gearshape"
            case .lyrics: "captions.bubble"
            case .hiddenApps: "eye.slash"
            case .experiments: "flask"
            }
        }
    }

    @State private var selectedSection: Section? = .general
    @FocusState private var focusedSection: Section?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "设置"))
                    .font(.system(size: 17, weight: .semibold))
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 12)

                VStack(spacing: 3) {
                    ForEach(Section.allCases) { section in
                        Button {
                            selectedSection = section
                            focusedSection = section
                        } label: {
                            Label {
                                Text(section.title)
                                    .font(.system(size: 13, weight: selectedSection == section ? .medium : .regular))
                            } icon: {
                                Image(systemName: section.icon)
                                    .symbolVariant(selectedSection == section ? .fill : .none)
                                    .font(.system(size: 13))
                                    .frame(width: 18)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(SettingsSidebarButtonStyle(isSelected: selectedSection == section))
                        .focusable()
                        .focusEffectDisabled()
                        .focused($focusedSection, equals: section)
                        .onMoveCommand { direction in
                            guard direction == .up || direction == .down,
                                  let index = Section.allCases.firstIndex(of: section) else { return }
                            let next = min(max(index + (direction == .down ? 1 : -1), 0), Section.allCases.count - 1)
                            focusedSection = Section.allCases[next]
                            selectedSection = Section.allCases[next]
                        }
                        .accessibilityAddTraits(selectedSection == section ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, 12)
                Spacer(minLength: 0)
                Text(versionText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
            }
            .frame(width: 190)
            .background(SettingsWindowMaterial(material: .sidebar))

            Rectangle().fill(.primary.opacity(0.06)).frame(width: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HStack(spacing: 8) {
                        Text((selectedSection ?? .general).title)
                            .font(.system(size: 24, weight: .semibold))
                        if selectedSection == .experiments {
                            Text("BETA")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                    }
                    switch selectedSection ?? .general {
                    case .general: generalSettings
                    case .lyrics: lyricsSettings
                    case .hiddenApps: hiddenAppSettings
                    case .experiments: experimentalSettings
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.88))
        }
        .background(SettingsWindowMaterial())
        .frame(minWidth: 660, minHeight: 500)
        .onAppear {
            model.refresh()
            runningApps = NSWorkspace.shared.runningApplications
        }
        .onChange(of: selectedSection) { _, _ in
            model.refresh()
            runningApps = NSWorkspace.shared.runningApplications
        }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 0) {
                settingRow(title: String(localized: "登录时自动启动")) {
                    Toggle("", isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
                        .labelsHidden().toggleStyle(.switch)
                        .accessibilityLabel(String(localized: "登录时自动启动"))
                }
                Divider().padding(.horizontal, 16)
                settingRow(title: String(localized: "自动检查更新")) {
                    Toggle("", isOn: Binding(get: { model.automaticallyChecksForUpdates }, set: model.setAutomaticallyChecksForUpdates))
                        .labelsHidden().toggleStyle(.switch)
                        .accessibilityLabel(String(localized: "自动检查更新"))
                }
            }
            .modifier(SettingsCardMaterial())
            if model.requiresLoginItemApproval {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Text(String(localized: "需要在系统设置的“登录项”中允许 Cueto。")).font(.caption)
                    Spacer()
                    Button(String(localized: "打开系统设置"), action: model.openLoginItemsSettings)
                }
            }
            if let errorMessage = model.errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(String(localized: "立即检查更新"), action: model.checkForUpdates)
                    .disabled(!model.canCheckForUpdates)
                    .keyboardShortcut("u", modifiers: [.command])
            }
        }
    }

    private var lyricsSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
#if CUETO_APPLE_MUSIC_LYRICS
                settingRow(title: String(localized: "Apple Music 歌词")) {
                    Toggle("", isOn: $appleLyrics.isEnabled)
                        .labelsHidden().toggleStyle(.switch)
                }
                if appleLyrics.isEnabled {
                    if !appleLyrics.usesDirectLyrics {
                        Text(String(localized: "歌曲信息发送至 LRCLIB，歌词缓存在本机。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 14)
                            .padding(.trailing, 14)
                    }
                    HStack(spacing: 12) {
                        Text(appleLyrics.currentText ?? (appleLyrics.showsMissingLyrics ? String(localized: "未读取到歌词") : ""))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(appleLyrics.currentText == nil ? .secondary : .primary)
                            .lineLimit(2, reservesSpace: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if appleLyrics.needsPermission || appleLyrics.showsMissingLyrics {
                            Button(appleLyrics.needsPermission ? String(localized: "授权…") : String(localized: "重试"), action: appleLyrics.retry)
                                .help(appleLyrics.statusMessage)
                        }
                        if !appleLyrics.isDirectConnected && appleLyrics.currentText == nil {
                            Button(String(localized: "连接…"), action: appleLyrics.openDirectProbe)
                                .accessibilityLabel(String(localized: "连接 Apple Music"))
                        } else {
                            Button(action: appleLyrics.openDirectProbe) {
                                Image(systemName: "ellipsis")
                            }
                            .accessibilityLabel(String(localized: "管理 Apple Music 连接…"))
                        }
                    }
                    .contextMenu {
                        if appleLyrics.isDirectConnected {
                            Button(String(localized: "管理 Apple Music 连接…"), action: appleLyrics.openDirectProbe)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.leading, 14)
                    .padding(.trailing, 14)
                    .padding(.bottom, 12)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "歌词校时"))
                            .font(.system(size: 12, weight: .medium))
                        LyricTimingControls(lyrics: appleLyrics)
                            .disabled(!appleLyrics.hasTimedLyrics)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
#endif
            }
            .modifier(SettingsCardMaterial())
            VStack(alignment: .leading, spacing: 0) {
                if subtitles.isEnabled || appleLyrics.isEnabled {
                    HStack(spacing: 16) {
                        Text(String(localized: "字幕宽度")).font(.system(size: 12))
                        Spacer(minLength: 0)
                        Picker(String(localized: "字幕宽度"), selection: $subtitles.width) {
                            ForEach(SubtitleWidth.allCases, id: \.self) { width in
                                Text(width.title).tag(width)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }


            }
        }
    }

    private var experimentalSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                settingRow(
                    title: String(localized: "菜单栏字幕 · 小宇宙")
                ) {
                    Toggle("", isOn: $subtitles.isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                Text(String(localized: "跨桌面时字幕可能停止更新。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)

                if subtitles.isEnabled && subtitles.currentText == nil {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: subtitles.needsPermission ? "lock.circle" : "info.circle")
                        Text(subtitles.statusMessage)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if subtitles.needsPermission {
                            Button(String(localized: "授权…"), action: subtitles.requestPermission)
                                .controlSize(.small)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }

                if let text = subtitles.currentText {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(text).font(.system(size: 13)).lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }


            }
            .modifier(SettingsCardMaterial())
            settingRow(title: String(localized: "灵动岛面板")) {
                Toggle("", isOn: $openPanelAtNotch)
                    .labelsHidden().toggleStyle(.switch)
                    .accessibilityLabel(String(localized: "灵动岛面板"))
                    .help(String(localized: "悬停 MacBook 刘海展开，移开后收起"))
            }
            .modifier(SettingsCardMaterial())
            VStack(alignment: .leading, spacing: 0) {
                settingRow(title: String(localized: "小宇宙异常退出后自动恢复")) {
                    Toggle("", isOn: $cosmosRecovery.isEnabled)
                        .labelsHidden().toggleStyle(.switch)
                        .accessibilityLabel(String(localized: "小宇宙异常退出后自动恢复"))
                        .help(String(localized: "仅在诊断报告确认已知的后台锁异常后重新打开，不发送播放指令。"))
                }
                if cosmosRecovery.isEnabled, let message = cosmosRecovery.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                }
            }
            .modifier(SettingsCardMaterial())
        }
    }

    private var hiddenAppSettings: some View {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Spacer()
                    Button(String(localized: "添加应用…"), action: chooseApplication)
                        .controlSize(.small)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(appChoices, id: \.identifier) { app in
                            Toggle(isOn: Binding(
                                get: { excludedApps.bundleIdentifiers.contains(app.identifier) },
                                set: { excludedApps.setExcluded($0, identifier: app.identifier, name: app.name) }
                            )) {
                                HStack(spacing: 9) {
                                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.identifier) {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                            .resizable()
                                            .frame(width: 18, height: 18)
                                    }
                                    Text(app.name)
                                        .lineLimit(1)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 300)
                .modifier(SettingsCardMaterial())
            }

    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "选择要隐藏的应用")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        excludedApps.setExcluded(true, identifier: identifier, name: name)
    }

    private func settingRow<Accessory: View>(
        title: String,
        detail: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
            accessory()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 17)
    }
}

private struct SettingsSidebarButtonStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && isEnabled
        let hovered = isHovered && isEnabled
        let opacity: Double = pressed ? 0.13 : (isSelected ? (hovered ? 0.085 : 0.055) : (hovered ? 0.035 : 0))
        configuration.label
            .foregroundStyle(Color.primary.opacity(isSelected || hovered || pressed ? 1 : 0.72))
            .background(Color.primary.opacity(opacity), in: RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { isHovered = $0 }
            .onDisappear { isHovered = false }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct SettingsCardMaterial: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.primary.opacity(0.09), lineWidth: 0.5)
            }
    }
}

private struct SettingsWindowMaterial: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
#endif
