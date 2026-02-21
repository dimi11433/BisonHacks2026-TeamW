import SwiftUI

struct WaveformView: View {
    let amplitudes: [CGFloat]
    let isActive: Bool
    let accentColor: Color
    
    init(
        amplitudes: [CGFloat] = Array(repeating: 0.1, count: 7),
        isActive: Bool = false,
        accentColor: Color = Color(hex: 0x00FFFF)
    ) {
        self.amplitudes = amplitudes
        self.isActive = isActive
        self.accentColor = accentColor
    }
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(amplitudes.enumerated()), id: \.offset) { index, amplitude in
                WaveformBar(
                    amplitude: amplitude,
                    isActive: isActive,
                    color: accentColor,
                    delay: Double(index) * 0.05
                )
            }
        }
        .frame(height: 40)
    }
}

private struct WaveformBar: View {
    let amplitude: CGFloat
    let isActive: Bool
    let color: Color
    let delay: Double
    
    @State private var animatedHeight: CGFloat = 0.1
    
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(
                LinearGradient(
                    colors: [color, color.opacity(0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 4, height: max(4, animatedHeight * 40))
            .shadow(color: color.opacity(isActive ? 0.6 : 0), radius: 4, y: 0)
            .onChange(of: amplitude) { _, newValue in
                withAnimation(.easeInOut(duration: 0.1).delay(delay)) {
                    animatedHeight = newValue
                }
            }
            .onChange(of: isActive) { _, active in
                if !active {
                    withAnimation(.easeOut(duration: 0.4)) {
                        animatedHeight = 0.1
                    }
                }
            }
    }
}
