import SwiftUI

struct ConnectionStatusView: View {
    let isConnected: Bool
    var source: CameraSource = .phone
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var appear = false
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "eyeglasses")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(isConnected ? Color(hex: 0x00FFFF) : .secondary)
            
            Text(isConnected ? "Connected" : "Phone Camera")
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(isConnected ? .white : .secondary)
            
            Circle()
                .fill(isConnected ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
                .scaleEffect(pulseScale)
                .onChange(of: isConnected) { _, connected in
                    if connected {
                        withAnimation(
                            .easeInOut(duration: 1.2)
                            .repeatForever(autoreverses: true)
                        ) {
                            pulseScale = 1.4
                        }
                    } else {
                        withAnimation(.easeOut(duration: 0.3)) {
                            pulseScale = 1.0
                        }
                    }
                }
                .onAppear {
                    guard isConnected else { return }
                    withAnimation(
                        .easeInOut(duration: 1.2)
                        .repeatForever(autoreverses: true)
                    ) {
                        pulseScale = 1.4
                    }
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.15), lineWidth: 0.5)
                )
        }
        .animation(.easeInOut(duration: 0.3), value: isConnected)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : -10)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4)) {
                appear = true
            }
        }
    }
}
