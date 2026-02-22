import SwiftUI

struct WLogoView: View {
    @State private var glowPhase: CGFloat = 0
    @State private var shimmerOffset: CGFloat = -200
    @State private var outerRingRotation: Double = 0
    @State private var innerPulse: CGFloat = 1.0

    private let cyan = Color(hex: 0x00FFFF)
    private let logoSize: CGFloat = 120

    var body: some View {
        ZStack {
            // Outer rotating ring
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [cyan.opacity(0.0), cyan.opacity(0.4), cyan.opacity(0.0)],
                        center: .center
                    ),
                    lineWidth: 1.5
                )
                .frame(width: 180, height: 180)
                .rotationEffect(.degrees(outerRingRotation))

            // Pulsing glow backdrop
            Circle()
                .fill(
                    RadialGradient(
                        colors: [cyan.opacity(0.15), cyan.opacity(0.0)],
                        center: .center,
                        startRadius: 30,
                        endRadius: 100
                    )
                )
                .frame(width: 200, height: 200)
                .scaleEffect(innerPulse)

            // Inner glass circle
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: logoSize, height: logoSize)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [cyan.opacity(0.6), cyan.opacity(0.1), cyan.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: cyan.opacity(0.3), radius: 24, y: 0)

            // The "W" letter
            Text("W")
                .font(.system(size: 52, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, cyan],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: cyan.opacity(0.6), radius: 12)
                .overlay(
                    Text("W")
                        .font(.system(size: 52, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white.opacity(0.0), .white.opacity(0.6), .white.opacity(0.0)],
                                startPoint: UnitPoint(x: shimmerOffset / 200, y: 0),
                                endPoint: UnitPoint(x: (shimmerOffset + 100) / 200, y: 1)
                            )
                        )
                )

            // Corner accent dots
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(cyan.opacity(0.5))
                    .frame(width: 4, height: 4)
                    .offset(y: -85)
                    .rotationEffect(.degrees(Double(i) * 90 + outerRingRotation * 0.5))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                outerRingRotation = 360
            }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                innerPulse = 1.12
            }
            withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                shimmerOffset = 200
            }
        }
    }
}

#Preview {
    ZStack {
        Color(hex: 0x0A0A0F).ignoresSafeArea()
        WLogoView()
    }
}
