import SwiftUI
import Combine

// MARK: - CPR Animation Overlay

struct CPRAnimationOverlay: View {
    let instruction: String
    let onDismiss: () -> Void

    @State private var compressionCount = 0
    private let compressionTimer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 460)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Dismiss
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 10)

                // Instruction banner
                Text(instruction)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 20)

                Spacer().frame(height: 22)

                // Animated CPR scene — TimelineView drives smooth frame-rate animation
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    let elapsed = timeline.date.timeIntervalSinceReferenceDate
                    let phase  = elapsed.truncatingRemainder(dividingBy: 0.6) / 0.6
                    let offset = CGFloat(compressionCurve(phase: phase)) * 52
                    let aAlpha = arrowAlpha(phase: phase)

                    CPRScene(handsOffset: offset, arrowAlpha: aAlpha)
                }
                .frame(height: 195)

                Spacer().frame(height: 16)

                // BPM + counter row
                HStack(spacing: 20) {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                        Text("100 BPM")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    Rectangle()
                        .fill(.white.opacity(0.2))
                        .frame(width: 1, height: 14)

                    Text("\(compressionCount) compressions")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .contentTransition(.numericText())
                        .animation(.linear(duration: 0.1), value: compressionCount)
                }

                Spacer().frame(height: 110)
            }
        }
        .onReceive(compressionTimer) { _ in
            compressionCount += 1
        }
    }

    // Quick press (ease-in quadratic), hold, linear release, short pause
    private func compressionCurve(phase: Double) -> Double {
        if phase < 0.35 {
            let t = phase / 0.35; return t * t
        } else if phase < 0.50 {
            return 1.0
        } else if phase < 0.85 {
            return 1.0 - (phase - 0.50) / 0.35
        }
        return 0.0
    }

    // Arrows brighten on the downstroke, fade after release
    private func arrowAlpha(phase: Double) -> Double {
        if phase < 0.35 { return phase / 0.35 }
        if phase < 0.55 { return 1.0 }
        return max(0, 1.0 - (phase - 0.55) / 0.30)
    }
}

// MARK: - Scene

private struct CPRScene: View {
    let handsOffset: CGFloat
    let arrowAlpha: Double

    var body: some View {
        ZStack(alignment: .center) {

            // Person torso outline
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(.white.opacity(0.18), lineWidth: 1.2)
                    .frame(width: 28, height: 16)          // neck hint

                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.28), lineWidth: 1.5)
                    .frame(width: 164, height: 80)         // chest
            }
            .offset(y: 44)

            // Red sternum target
            Circle()
                .fill(.red.opacity(0.7))
                .frame(width: 12, height: 12)
                .offset(y: 40)

            // Downward arrows — fade in on press, fade out on release
            VStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.cyan)
                        .opacity(arrowAlpha * max(0.2, 1.0 - Double(i) * 0.3))
                }
            }
            .offset(y: -76 + handsOffset * 0.35)
            .opacity(arrowAlpha)

            // Speed lines beside the hands during downstroke
            Canvas { ctx, size in
                let alpha = arrowAlpha * 0.4
                guard alpha > 0.02 else { return }
                let lc = GraphicsContext.Shading.color(.white.opacity(alpha))
                let cx = size.width / 2
                let pairs: [(CGFloat, CGFloat, CGFloat)] = [
                    (-58,  8, 18),
                    (-44,  4, 14),
                    ( 44,  4, 14),
                    ( 58,  8, 18),
                ]
                for (xOff, yStart, yEnd) in pairs {
                    var p = Path()
                    p.move(to:    CGPoint(x: cx + xOff, y: yStart))
                    p.addLine(to: CGPoint(x: cx + xOff, y: yEnd))
                    ctx.stroke(p, with: lc, lineWidth: 1.8)
                }
            }
            .frame(width: 180, height: 30)
            .offset(y: -18 + handsOffset + 28)

            // Stacked hands — line-art SF Symbols, animate down with compression
            ZStack {
                // Bottom hand — dimmer, slightly smaller for depth
                Image(systemName: "hand.raised")
                    .font(.system(size: 60, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.45))
                    .rotationEffect(.degrees(180))
                    .scaleEffect(0.9)
                    .offset(x: 2, y: 7)

                // Top hand — bright
                Image(systemName: "hand.raised")
                    .font(.system(size: 60, weight: .ultraLight))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(180))
            }
            .offset(y: -20 + handsOffset)
        }
    }
}
