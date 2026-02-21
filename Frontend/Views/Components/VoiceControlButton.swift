import SwiftUI

struct VoiceControlButton: View {
    let state: VoiceTriggerState
    let waveformAmplitudes: [CGFloat]
    let onTap: () -> Void
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var appear = false
    
    private let cyan = Color(hex: 0x00FFFF)
    
    var body: some View {
        VStack(spacing: 14) {
            // Waveform visualization
            WaveformView(
                amplitudes: waveformAmplitudes,
                isActive: state == .listening,
                accentColor: cyan
            )
            .frame(width: 120)
            .opacity(state == .listening ? 1 : 0.3)
            
            // Main button
            Button(action: onTap) {
                ZStack {
                    // Outer pulse ring
                    Circle()
                        .fill(cyan.opacity(0.08))
                        .frame(width: 80, height: 80)
                        .scaleEffect(pulseScale)
                    
                    // Glass ring
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 64, height: 64)
                        .overlay(
                            Circle()
                                .stroke(
                                    state == .listening ? cyan : .white.opacity(0.2),
                                    lineWidth: state == .listening ? 2 : 0.5
                                )
                        )
                        .shadow(color: state == .listening ? cyan.opacity(0.4) : .clear, radius: 12)
                    
                    // Icon
                    Image(systemName: state.icon)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(state == .listening ? cyan : .white.opacity(0.8))
                        .symbolEffect(.variableColor, isActive: state == .processing)
                }
            }
            .buttonStyle(.plain)
            
            // State label
            Text(state.label)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(state == .listening ? cyan : .white.opacity(0.5))
        }
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 20)
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
