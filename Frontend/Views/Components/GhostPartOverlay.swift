import SwiftUI

struct GhostPartOverlay: View {
    let isVisible: Bool
    
    @State private var rotationAngle: Double = 0
    @State private var pulseOpacity: Double = 0.3
    
    private let cyan = Color(hex: 0x00FFFF)
    
    var body: some View {
        ZStack {
            // Outer scan ring
            Circle()
                .stroke(cyan.opacity(pulseOpacity * 0.4), lineWidth: 1)
                .frame(width: 220, height: 220)
            
            // Rotating corner brackets (3D bounding box feel)
            ForEach(0..<4, id: \.self) { corner in
                BracketCorner()
                    .stroke(cyan.opacity(0.7), lineWidth: 1.5)
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(Double(corner) * 90))
            }
            .rotationEffect(.degrees(rotationAngle))
            
            // Inner crosshair
            CrosshairShape()
                .stroke(cyan.opacity(0.3), lineWidth: 0.5)
                .frame(width: 180, height: 180)
            
            // Center target dot
            Circle()
                .fill(cyan.opacity(pulseOpacity))
                .frame(width: 8, height: 8)
            
            // "Place Part Here" label
            VStack(spacing: 4) {
                Spacer()
                
                Text("SCAN TARGET")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(cyan.opacity(0.6))
                    .tracking(2)
                
                Text("Point at anything to get started")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(height: 280)
        }
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulseOpacity = 0.8
            }
        }
    }
}

// MARK: - Bracket Corner Shape

private struct BracketCorner: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let length: CGFloat = 20
        
        // Top-left corner bracket
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
        
        return path
    }
}

// MARK: - Crosshair Shape

private struct CrosshairShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let gap: CGFloat = 20
        let armLength: CGFloat = rect.width / 2
        
        // Horizontal arms
        path.move(to: CGPoint(x: center.x - armLength, y: center.y))
        path.addLine(to: CGPoint(x: center.x - gap, y: center.y))
        path.move(to: CGPoint(x: center.x + gap, y: center.y))
        path.addLine(to: CGPoint(x: center.x + armLength, y: center.y))
        
        // Vertical arms
        path.move(to: CGPoint(x: center.x, y: center.y - armLength))
        path.addLine(to: CGPoint(x: center.x, y: center.y - gap))
        path.move(to: CGPoint(x: center.x, y: center.y + gap))
        path.addLine(to: CGPoint(x: center.x, y: center.y + armLength))
        
        return path
    }
}
