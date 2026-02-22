import SwiftUI

struct VoiceControlButton: View {
    let state: VoiceTriggerState
    let waveformAmplitudes: [CGFloat]
    let onTap: () -> Void
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var appear = false
    
    private let cyan = Color(hex: 0x00FFFF)
    private let orange = Color.orange
    
    private var accentColor: Color {
        state == .listening ? cyan : orange
    }
    
    var body: some View {
        VStack(spacing: 14) {
            WaveformView(
                amplitudes: waveformAmplitudes,
                isActive: state == .listening,
                accentColor: cyan
            )
            .frame(width: 120)
            .opacity(state == .listening ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: state)
            
            Button(action: onTap) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.08))
                        .frame(width: 80, height: 80)
                        .scaleEffect(pulseScale)
                    
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 64, height: 64)
                        .overlay(
                            Circle()
                                .stroke(accentColor, lineWidth: 2)
                        )
                        .shadow(color: accentColor.opacity(0.4), radius: 12)
                    
                    Image(systemName: state.icon)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
            }
            .buttonStyle(.plain)
            
            Text(state.label)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(accentColor)
        }
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 20)
        .animation(.easeInOut(duration: 0.25), value: state)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.6)) {
                appear = true
            }
            withAnimation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true)
            ) {
                pulseScale = 1.15
            }
        }
    }
}
