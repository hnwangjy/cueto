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
                    Text(String(localized: "当前没有音频正在播放"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !playback.availableAudioSources.isEmpty {
                AudioProcessList(playback: playback)
            }

            Divider()

            HStack {
                Button(String(localized: "打开 Cueto"), action: onOpenCueto)
                Spacer()
                Button(String(localized: "退出"), action: onQuit)
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
            HStack(alignment: .center, spacing: 14) {
                if let artwork = playback.artwork {
                    Image(nsImage: artwork)
                        .resizable().scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                        }
                        .accessibilityLabel(String(localized: "当前播放封面"))
                } else if let icon = playback.applicationIcon {
                    Image(nsImage: icon)
                        .resizable().scaledToFit()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 4) {
                        Text(playback.applicationName)
                        Text("·")
                        Text(playback.isPlaying ? String(localized: "正在播放") : String(localized: "已暂停"))
                        Spacer(minLength: 8)
                        if playback.artwork != nil, let icon = playback.applicationIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                                .accessibilityHidden(true)
                                .help(playback.applicationName)
                        }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    Text(playback.title ?? playback.applicationName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let artist = playback.artist {
                        Text(artist)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let elapsedTime = playback.elapsedTime,
               let duration = playback.duration,
               duration > 0 {
                playbackProgress(elapsedTime: elapsedTime, duration: duration)
            }

            let showsAppleLyrics = appleLyrics.isEnabled &&
                (appleLyrics.isPlaying || playback.bundleIdentifier == "com.apple.Music")
            let text = showsAppleLyrics ? appleLyrics.currentText : subtitles.currentText
            if showsAppleLyrics {
                AppleMusicLyricsPanel(lyrics: appleLyrics)
            } else if let text {
                VStack(alignment: .leading, spacing: 6) {
                    Label(String(localized: "小宇宙字幕"), systemImage: "captions.bubble")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(text)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .lineLimit(2, reservesSpace: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            }

            if !playback.availableAudioSources.isEmpty {
                AudioProcessList(playback: playback)
            }

            Divider()

            HStack {
                Button(String(localized: "打开 Cueto")) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        onOpenCueto()
                    }
                }
                Spacer()
                Button(String(localized: "退出"), action: onQuit)
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
                .accessibilityLabel(String(localized: "播放进度"))
                .accessibilityValue(String(localized: "已播放 \(formatTime(elapsed))，总时长 \(formatTime(duration))"))

            HStack(spacing: 8) {
                Text(formatTime(elapsed))
                    .accessibilityLabel(String(localized: "已播放 \(formatTime(elapsed))"))
                Spacer()
                Text(String(localized: "共 \(formatTime(duration))"))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(String(localized: "总时长 \(formatTime(duration))"))
                Spacer()
                Text("−\(formatTime(remaining))")
                    .accessibilityLabel(String(localized: "剩余 \(formatTime(remaining))"))
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

struct AppleMusicLyricsPanel: View {
    @ObservedObject var lyrics: AppleMusicLyricsMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "Apple Music 歌词"), systemImage: "captions.bubble")
                .font(.caption)
                .foregroundStyle(.secondary)

            if lyrics.hasTimedLyrics {
                VStack(spacing: 2) {
                    lyricRow(lyrics.lyricContext.previous, current: false)
                    lyricRow(lyrics.lyricContext.current, current: true)
                    lyricRow(lyrics.lyricContext.next, current: false)
                }

                if let error = lyrics.seekError {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(lyrics.showsMissingLyrics ? String(localized: "未读取到歌词") : "")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func lyricRow(_ cue: LyricCue?, current: Bool) -> some View {
        Button {
            if let cue { lyrics.seek(to: cue) }
        } label: {
            HStack(spacing: 8) {
                Text(cue?.text ?? (current ? String(localized: "间奏") : ""))
                    .font(.system(size: 13, weight: current ? .semibold : .regular))
                    .foregroundStyle(current && cue != nil ? .primary : .secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let cue {
                    Text(String(format: "%d:%02d", Int(cue.time) / 60, Int(cue.time) % 60))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(LyricLineButtonStyle(current: current && cue != nil))
        .disabled(cue == nil || lyrics.isSeeking)
        .help(cue == nil ? "" : String(localized: "点击歌词跳转"))
    }
}

struct LyricTimingControls: View {
    @ObservedObject var lyrics: AppleMusicLyricsMonitor

    var body: some View {
        HStack(spacing: 8) {
            Button {
                lyrics.adjustTiming(by: 0.5)
            } label: {
                Label(String(localized: "提前"), systemImage: "minus")
            }
            .disabled(lyrics.timingOffset >= 10)
            Spacer(minLength: 0)
            Button(action: lyrics.resetTiming) {
                Text(lyrics.timingOffset == 0 ? String(localized: "同步") :
                        String(format: "%+.1f s", -lyrics.timingOffset))
                    .monospacedDigit()
                    .frame(minWidth: 52)
            }
            .disabled(lyrics.timingOffset == 0)
            .help(String(localized: "恢复原始时间"))
            Spacer(minLength: 0)
            Button {
                lyrics.adjustTiming(by: -0.5)
            } label: {
                Label(String(localized: "延后"), systemImage: "plus")
            }
            .disabled(lyrics.timingOffset <= -10)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 4)
        .frame(height: 26)
    }
}

private struct LyricLineButtonStyle: ButtonStyle {
    let current: Bool
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                current ? Color.accentColor.opacity(configuration.isPressed ? 0.18 : 0.10) :
                    Color.primary.opacity(configuration.isPressed ? 0.10 : (hovered ? 0.05 : 0)),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .onHover { hovered = $0 }
    }
}

struct AudioProcessList: View {
    @ObservedObject var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "音频应用"))
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(String(localized: "\(playback.availableAudioSources.count) 个"))
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
                                            .accessibilityLabel(String(localized: "当前来源"))
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
                                    Text(String(localized: "前往"))
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                            }
                            .buttonStyle(SourceNavigationButtonStyle())
                            .help(String(localized: "打开并切换到 \(source.applicationName)"))
                            .accessibilityLabel(String(localized: "前往 \(source.applicationName)"))
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
            return playback.isPlaying ? String(localized: "当前播放") : String(localized: "已暂停")
        }
        if playback.activeAudioSources.contains(where: { $0.bundleIdentifier == source.bundleIdentifier }) {
            return String(localized: "正在播放")
        }
        return source.isRunningOutput ? String(localized: "音频流活跃") : String(localized: "未输出音频")
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
