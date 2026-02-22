import SwiftUI
import Combine

// MARK: - CPR Animation Overlay

struct CPRAnimationOverlay: View {
    let instruction: String
    let onDismiss: () -> Void
    var anchorX: Double?
    var anchorY: Double?

    @State private var compressionCount = 0

    private let compressionTimer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let hasAnchor = anchorX != nil && anchorY != nil
            let animScale: CGFloat = hasAnchor ? 0.7 : 1.0

            ZStack {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: hasAnchor ? 300 : 420)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button(action: onDismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }
                    .padding(.horizontal, 24)

                    Spacer().frame(height: 10)

                    Text(instruction)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 20)

                    Spacer().frame(height: 20)

                    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                        let elapsed = timeline.date.timeIntervalSinceReferenceDate
                        let phase = elapsed.truncatingRemainder(dividingBy: 0.6) / 0.6
                        let offset = CGFloat(compressionCurve(phase: phase)) * 44

                        CPRSceneView(handsOffset: offset)
                    }
                    .frame(height: 170 * animScale)
                    .scaleEffect(animScale)

                    Spacer().frame(height: 18)

                    HStack(spacing: 22) {
                        HStack(spacing: 7) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                            Text("100 BPM")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                        Rectangle()
                            .fill(.white.opacity(0.25))
                            .frame(width: 1, height: 16)

                        Text("\(compressionCount) compressions")
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .contentTransition(.numericText())
                            .animation(.linear(duration: 0.1), value: compressionCount)
                    }

                    Spacer().frame(height: 110)
                }
            }
        }
        .onReceive(compressionTimer) { _ in
            compressionCount += 1
        }
    }

    // Returns 0.0 (hands up) → 1.0 (hands fully pressed) for a given cycle phase.
    // Shape: quick press down, brief hold, controlled release, short pause.
    private func compressionCurve(phase: Double) -> Double {
        let pressEnd   = 0.35  // first 35% — press down
        let holdEnd    = 0.50  // next 15% — hold at bottom
        let releaseEnd = 0.85  // next 35% — release up

        if phase < pressEnd {
            // Ease-in quadratic for a quick, snappy press
            let t = phase / pressEnd
            return t * t
        } else if phase < holdEnd {
            return 1.0
        } else if phase < releaseEnd {
            let t = (phase - holdEnd) / (releaseEnd - holdEnd)
            return 1.0 - t
        } else {
            return 0.0  // pause at top before next compression
        }
    }
}

// MARK: - CPR Scene

private struct CPRSceneView: View {
    let handsOffset: CGFloat

    var body: some View {
        ZStack {
            // Person silhouette
            VStack(spacing: 0) {
                Circle()
                    .stroke(.white.opacity(0.28), lineWidth: 1.5)
                    .frame(width: 36, height: 36)

                RoundedRectangle(cornerRadius: 14)
                    .fill(.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(.white.opacity(0.22), lineWidth: 1.5)
                    )
                    .frame(width: 130, height: 90)
            }
            .offset(y: 8)

            // Red target spot on sternum
            Circle()
                .fill(.red.opacity(0.65))
                .frame(width: 20, height: 20)
                .offset(y: 28)

            // Stacked hands that move down with handsOffset
            VStack(spacing: -5) {
                CPRHandView(opacity: 1.0)
                CPRHandView(opacity: 0.72)
            }
            .offset(y: -14 + handsOffset)

            // Depth indicator on the right
            VStack(spacing: 5) {
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.12))
                        .frame(width: 8, height: 54)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(handsOffset > 35 ? Color.green : Color.orange)
                        .frame(width: 8, height: max(2, handsOffset / 44 * 54))
                }

                Text("depth")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .offset(x: 96, y: 8)
        }
    }
}

// MARK: - Hand Shape

private struct CPRHandView: View {
    let opacity: Double

    var body: some View {
        ZStack(alignment: .top) {
            // Palm
            RoundedRectangle(cornerRadius: 7)
                .fill(.white.opacity(opacity))
                .frame(width: 72, height: 22)
                .offset(y: 14)

            // Four fingers
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { _ in
                    Capsule()
                        .fill(.white.opacity(opacity))
                        .frame(width: 12, height: 17)
                }
            }
        }
        .frame(width: 72, height: 36)
    }
}
