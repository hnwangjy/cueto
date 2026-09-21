#if os(macOS)
import SwiftUI

struct NowPlayingPopover: View {
    @ObservedObject var playback: PlaybackController
    let onOpenCueto: () -> Void
    let onQuit: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if playback.activeAudioSourceCount > 1 {
                activeAudioSources
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
        .frame(width: 278)
    }

    private var activeAudioSources: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("正在发声 · \(playback.activeAudioSourceCount)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(playback.activeAudioSources) { source in
                HStack(spacing: 8) {
                    if let icon = source.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    Text(source.applicationName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    if source.bundleIdentifier == playback.bundleIdentifier {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .accessibilityLabel("当前控制")
                    } else {
                        Text("正在发声")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(minHeight: 22)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
#endif
