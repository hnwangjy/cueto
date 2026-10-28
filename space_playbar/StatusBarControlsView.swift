#if os(macOS)
import SwiftUI

struct IdlePopover: View {
    @ObservedObject var playback: PlaybackController
    let onOpenCueto: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.mid")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Cueto")
                        .font(.headline)
                    Text("当前没有音频正在播放")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !playback.availableAudioSources.isEmpty {
                AudioProcessList(playback: playback)
            }

            Divider()

            HStack {
                Button("打开 Cueto", action: onOpenCueto)
                Spacer()
                Button("退出", action: onQuit)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
        }
        .padding(16)
        .frame(width: playback.availableAudioSources.isEmpty ? 250 : 350)
    }
}

struct NowPlayingPopover: View {
    @ObservedObject var playback: PlaybackController
    @ObservedObject var subtitles: CosmosSubtitleMonitor
    @ObservedObject var appleLyrics: AppleMusicLyricsMonitor
    let onOpenCueto: () -> Void
    let onQuit: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !playback.availableAudioSources.isEmpty {
                AudioProcessList(playback: playback)
            }

            HStack(spacing: 10) {
                if let icon = playback.applicationIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(playback.applicationName)
                        .font(.headline)
                    Text(playback.isPlaying ? "正在播放" : "已暂停")
                        .font(.caption)
                        .foregroundStyle(playback.isPlaying ? Color.accentColor : .secondary)
                }
            }

            if let title = playback.title {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                    if let artist = playback.artist {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            if let elapsedTime = playback.elapsedTime,
               let duration = playback.duration,
               duration > 0 {
                playbackProgress(elapsedTime: elapsedTime, duration: duration)
            }

            if let text = appleLyrics.isEnabled && (appleLyrics.isPlaying || playback.bundleIdentifier == "com.apple.Music") ? appleLyrics.currentText : subtitles.currentText {
                VStack(alignment: .leading, spacing: 6) {
                    Label(appleLyrics.isEnabled && (appleLyrics.isPlaying || playback.bundleIdentifier == "com.apple.Music") ? "Apple Music 歌词" : "小宇宙字幕", systemImage: "captions.bubble")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            }

            Divider()

            HStack {
                Button("打开 Cueto") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        onOpenCueto()
                    }
                }
                Spacer()
                Button("退出", action: onQuit)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
        }
        .padding(16)
        .frame(width: 350)
    }

    private func playbackProgress(elapsedTime: TimeInterval, duration: TimeInterval) -> some View {
        let elapsed = min(max(elapsedTime, 0), duration)
        let remaining = max(duration - elapsed, 0)

        return VStack(spacing: 6) {
            ProgressView(value: elapsed, total: duration)
                .progressViewStyle(.linear)
                .tint(.accentColor)
                .accessibilityLabel("播放进度")
                .accessibilityValue("已播放 \(formatTime(elapsed))，总时长 \(formatTime(duration))")

            HStack(spacing: 8) {
                Text(formatTime(elapsed))
                    .accessibilityLabel("已播放 \(formatTime(elapsed))")
                Spacer()
                Text("共 \(formatTime(duration))")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("总时长 \(formatTime(duration))")
                Spacer()
                Text("−\(formatTime(remaining))")
                    .accessibilityLabel("剩余 \(formatTime(remaining))")
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let totalSeconds = max(Int(interval.rounded(.down)), 0)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct AudioProcessList: View {
    @ObservedObject var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("音频应用")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(playback.availableAudioSources.count) 个")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(playback.availableAudioSources) { source in
                        HStack(spacing: 10) {
                            if let icon = source.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 26, height: 26)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 5) {
                                    Text(source.applicationName)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                    if source.bundleIdentifier == playback.bundleIdentifier {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Color.accentColor)
                                            .accessibilityLabel("当前来源")
                                    }
                                }
                                Text(statusText(for: source))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Button {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    playback.openApplication(for: source)
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Text("前往")
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                            }
                            .buttonStyle(SourceNavigationButtonStyle())
                            .help("打开并切换到 \(source.applicationName)")
                            .accessibilityLabel("前往 \(source.applicationName)")
                        }
                        .disabled(playback.openingSourceIdentifier != nil)
                        .padding(.horizontal, 8)
                        .frame(height: 44)
                        .background(
                            Color.accentColor.opacity(source.bundleIdentifier == playback.bundleIdentifier ? 0.06 : 0),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                    }
                }
            }
            .frame(height: min(max(CGFloat(playback.availableAudioSources.count) * 48 - 4, 0), 236))
            if let error = playback.sourceOpenError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .padding(.top, 3)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statusText(for source: ActiveAudioSource) -> String {
        if source.bundleIdentifier == playback.bundleIdentifier && playback.hasActiveSession {
            return playback.isPlaying ? "当前播放" : "已暂停"
        }
        if playback.activeAudioSources.contains(where: { $0.bundleIdentifier == source.bundleIdentifier }) {
            return "正在播放"
        }
        return source.isRunningOutput ? "音频流活跃" : "未输出音频"
    }
}

private struct SourceNavigationButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background {
                ZStack {
                    Capsule().fill(Color(nsColor: .controlBackgroundColor))
                    Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.14 : (isHovered ? 0.07 : 0)))
                }
            }
            .overlay(Capsule().strokeBorder(Color.primary.opacity(isHovered ? 0.3 : 0.2), lineWidth: 1))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { isHovered = $0 }
    }
}
#endif
