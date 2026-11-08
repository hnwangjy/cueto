#if os(macOS) && CUETO_APPLE_MUSIC_LYRICS
import SwiftUI

/// A short illustrated sequence for each connection step.
struct AppleMusicGuideMotion: View {
    let step: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            scene(phase: 3)
        } else {
            scene(phase: 0)
                .phaseAnimator([0, 1, 2, 3, 4, 5, 6]) { _, phase in
                    scene(phase: phase == 6 ? 0 : min(phase, 3))
                        .opacity(phase >= 5 ? 0 : 1)
                } animation: { phase in
                    switch phase {
                    case 0: .easeInOut(duration: 0.4)
                    case 1: .spring(duration: 0.55, bounce: 0.22)
                    case 2: .easeInOut(duration: 0.6)
                    case 3: .spring(duration: 0.5, bounce: 0.18)
                    case 4: .linear(duration: 1.4)
                    case 5: .easeInOut(duration: 0.35)
                    default: .linear(duration: 0.65)
                    }
                }
        }
    }

    private func scene(phase: Int) -> some View {
        ZStack {
            if step == 0 {
                login(phase: phase)
            } else if step == 1 {
                trust(phase: phase)
            } else {
                lyrics(phase: phase)
            }
        }
        .frame(width: 300, height: 116)
    }

    private func login(phase: Int) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(0..<3) { _ in
                    Circle().fill(.tertiary).frame(width: 3, height: 3)
                }
                Spacer()
            }
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 9) {
                    Capsule().fill(Color.primary.opacity(0.2))
                        .frame(width: 66, height: 5)
                    HStack(spacing: 5) {
                        ForEach(0..<5) { index in
                            Circle().fill(Color.primary.opacity(0.45))
                                .frame(width: 4, height: 4)
                                .opacity(phase >= 2 ? 1 : 0.15)
                                .animation(.easeInOut(duration: 0.2).delay(Double(index) * 0.09), value: phase)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: phase >= 3 ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .padding(16)
        .frame(width: 208, height: 96)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.08)) }
    }

    private func trust(phase: Int) -> some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor.opacity(0.12), lineWidth: 2)
                .frame(width: 66, height: 66)
            Circle()
                .trim(from: 0, to: phase >= 2 ? 1 : 0)
                .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 66, height: 66)
            Image(systemName: "shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor.opacity(0.16))
                .scaleEffect(phase >= 1 ? 1 : 0.8)
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .scaleEffect(phase >= 3 ? 1 : 0.5)
                .opacity(phase >= 3 ? 1 : 0)
        }
        .frame(width: 208, height: 96)
    }

    private func lyrics(phase: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(Color.accentColor.opacity(0.7))
                        .scaleEffect(x: phase >= 2 ? 1 : 0.15, anchor: .leading)
                }
                .frame(width: 70, height: 4)
                Spacer()
                Image(systemName: "music.note").font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 27)
            .background(Color.primary.opacity(0.04))
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
            HStack(spacing: 12) {
                Image(systemName: "music.note")
                    .font(.system(size: 19))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 7) {
                    Capsule().fill(Color.primary.opacity(0.22)).frame(width: 64, height: 5)
                    Capsule().fill(Color.primary.opacity(0.1)).frame(width: 42, height: 4)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
                    .scaleEffect(phase >= 3 ? 1 : 0.85)
                    .opacity(phase >= 3 ? 1 : 0.2)
            }
            .padding(.horizontal, 14)
            .frame(maxHeight: .infinity)
        }
        .frame(width: 208, height: 96)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.08)) }
    }
}
#endif
