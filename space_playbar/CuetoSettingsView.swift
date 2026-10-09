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

    init(updater: SPUUpdater) {
        self.updater = updater
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
            errorMessage = "无法更改开机启动设置：\(error.localizedDescription)"
        }
        refresh()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updater.automaticallyChecksForUpdates = enabled
        objectWillChange.send()
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}

struct CuetoSettingsView: View {
    @ObservedObject var model: CuetoSettingsModel
    @ObservedObject var excludedApps: ExcludedAudioApps
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
        return "版本 \(version)（\(build)）"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                if let icon = NSApplication.shared.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Cueto")
                        .font(.system(size: 22, weight: .semibold))
                    Text("让正在播放的声音始终触手可及")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text(versionText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            VStack(spacing: 0) {
                settingRow(
                    icon: "power",
                    title: "登录时自动启动",
                    detail: "登录 Mac 后自动在菜单栏运行 Cueto"
                ) {
                    Toggle("", isOn: Binding(
                        get: { model.launchAtLogin },
                        set: model.setLaunchAtLogin
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                Divider().padding(.leading, 44)

                settingRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "自动检查更新",
                    detail: "定期在后台检查是否有新版本"
                ) {
                    Toggle("", isOn: Binding(
                        get: { model.automaticallyChecksForUpdates },
                        set: model.setAutomaticallyChecksForUpdates
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("隐藏应用")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button("添加应用…", action: chooseApplication)
                        .controlSize(.small)
                }
                Text("勾选后，该应用不会出现在控制栏、数量角标或播放来源列表中。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
                .frame(height: 130)
                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
            }

            if model.requiresLoginItemApproval {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text("需要在系统设置的“登录项”中允许 Cueto。")
                        .font(.caption)
                    Spacer()
                    Button("打开系统设置", action: model.openLoginItemsSettings)
                        .controlSize(.small)
                }
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Text("更新检查由 Sparkle 安全执行")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("立即检查更新", action: model.checkForUpdates)
                    .disabled(!model.canCheckForUpdates)
                    .keyboardShortcut("u", modifiers: [.command])
            }
        }
        .padding(26)
        .frame(minWidth: 440, minHeight: 500)
        .onAppear {
            model.refresh()
            runningApps = NSWorkspace.shared.runningApplications
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "选择要隐藏的应用"
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
        icon: String,
        title: String,
        detail: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            accessory()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
#endif
