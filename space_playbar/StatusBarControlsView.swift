#if os(macOS)
import SwiftUI

struct StatusBarControlsView: View {
    @ObservedObject var playback: PlaybackController
    let onQuit: () -> Void
    @State private var isInfoPresented = false

    var body: some View {
        HStack(spacing: 3) {
            sourceButton

            Divider()
                .frame(height: 14)
                .padding(.horizontal, 2)

            controlButton("gobackward.15", label: "后退 15 秒", action: playback.skipBackward)
            controlButton(
                playback.isPlaying ? "pause.fill" : "play.fill",
                label: playback.isPlaying ? "暂停" : "播放",
                action: playback.playPause
            )
            controlButton("goforward.30", label: "前进 30 秒", action: playback.skipForward)
        }
        .padding(.horizontal, 4)
        .frame(maxHeight: .infinity)
        .opacity(playback.hasActiveSession ? 1 : 0.62)
        .contextMenu {
            if playback.hasActiveSession {
                Button("打开 \(playback.applicationName)", action: playback.openSourceApplication)
                Divider()
            }
            Button("退出 NowKeys", action: onQuit)
        }
        .animation(.easeOut(duration: 0.14), value: playback.isPlaying)
        .animation(.easeOut(duration: 0.14), value: playback.applicationName)
    }

    private var sourceButton: some View {
        Button { isInfoPresented.toggle() } label: {
            HStack(spacing: 6) {
                sourceIcon
                Text(playback.applicationName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: true, vertical: false)
            .contentShape(Rectangle())
        }
        .buttonStyle(StatusBarButtonStyle(horizontalPadding: 5))
        .help("查看当前播放来源")
        .disabled(!playback.hasActiveSession)
        .popover(isPresented: $isInfoPresented, arrowEdge: .bottom) {
            NowPlayingPopover(playback: playback, onQuit: onQuit)
        }
    }

    @ViewBuilder
    private var sourceIcon: some View {
        if let icon = playback.applicationIcon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
        } else {
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 15)
        }
    }

    private func controlButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .contentTransition(.symbolEffect(.replace))
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 27, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(StatusBarButtonStyle(horizontalPadding: 0))
        .help(label)
        .disabled(!playback.hasActiveSession)
        .accessibilityLabel(label)
    }
}

private struct NowPlayingPopover: View {
    @ObservedObject var playback: PlaybackController
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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

            Divider()

            HStack {
                Button("打开应用", action: playback.openSourceApplication)
                Spacer()
                Button("退出", action: onQuit)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
        }
        .padding(16)
        .frame(width: 238)
    }
}

private struct StatusBarButtonStyle: ButtonStyle {
    let horizontalPadding: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, horizontalPadding)
            .foregroundStyle(.primary)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.13) : .clear)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
#endif
