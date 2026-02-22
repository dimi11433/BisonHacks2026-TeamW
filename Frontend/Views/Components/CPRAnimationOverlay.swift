import SwiftUI
import Combine
import Lottie

struct CPRAnimationOverlay: View {
    let animationName: String
    let instruction: String
    let onDismiss: () -> Void
    var anchorX: Double?
    var anchorY: Double?

    @State private var compressionCount = 0

    private let compressionTimer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()

    private var isCompressions: Bool { animationName == "cpr_compressions" }

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

                    LottieView(animation: .named(animationName))
                        .looping()
                        .frame(width: 200 * animScale, height: 200 * animScale)

                    Spacer().frame(height: 18)

                    if isCompressions {
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
                    }

                    Spacer().frame(height: 110)
                }
            }
        }
        .onReceive(compressionTimer) { _ in
            if isCompressions {
                compressionCount += 1
            }
        }
    }
}
