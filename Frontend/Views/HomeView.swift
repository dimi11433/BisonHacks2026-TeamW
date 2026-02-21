import SwiftUI

struct HomeView: View {
    @State private var showAssembly = false
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0
    @State private var contentOpacity: Double = 0
    @State private var buttonOffset: CGFloat = 30
    @State private var pulseRing: CGFloat = 1.0
    
    private let cyan = Color(hex: 0x00FFFF)
    
    var body: some View {
        ZStack {
            // Dark background with subtle gradient
            LinearGradient(
                colors: [
                    Color(hex: 0x0A0A0F),
                    Color(hex: 0x0D1117),
                    Color(hex: 0x0A0A0F)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Subtle grid pattern
            GridPatternView()
                .opacity(0.04)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Logo + branding
                VStack(spacing: 20) {
                    ZStack {
                        // Pulse rings
                        Circle()
                            .stroke(cyan.opacity(0.08), lineWidth: 1)
                            .frame(width: 160, height: 160)
                            .scaleEffect(pulseRing)
                        
                        Circle()
                            .stroke(cyan.opacity(0.05), lineWidth: 1)
                            .frame(width: 200, height: 200)
                            .scaleEffect(pulseRing * 0.95)
                        
                        // Icon container
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 100, height: 100)
                            .overlay(
                                Circle()
                                    .stroke(cyan.opacity(0.3), lineWidth: 1)
                            )
                            .shadow(color: cyan.opacity(0.2), radius: 20)
                        
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 38, weight: .light, design: .rounded))
                            .foregroundStyle(cyan)
                    }
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                    
                    VStack(spacing: 8) {
                        Text("Spatial Assembly")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        
                        Text("Assistant")
                            .font(.system(size: 28, weight: .light, design: .rounded))
                            .foregroundStyle(cyan)
                        
                        Text("Voice-guided AR furniture assembly")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.top, 4)
                    }
                    .opacity(logoOpacity)
                }
                
                Spacer()
                
                // Connection + status cards
                VStack(spacing: 12) {
                    StatusRow(
                        icon: "eyeglasses",
                        title: "Meta Ray-Ban",
                        subtitle: "Ready to connect",
                        accentColor: cyan
                    )
                    
                    StatusRow(
                        icon: "camera.viewfinder",
                        title: "AR Engine",
                        subtitle: "RealityKit active",
                        accentColor: .green
                    )
                    
                    StatusRow(
                        icon: "mic.badge.plus",
                        title: "Voice Control",
                        subtitle: "Tap mic to speak commands",
                        accentColor: .purple
                    )
                }
                .padding(.horizontal, 24)
                .opacity(contentOpacity)
                
                Spacer().frame(height: 40)
                
                // Start button
                Button {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        showAssembly = true
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                        
                        Text("Start Live")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(cyan, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(color: cyan.opacity(0.4), radius: 16, y: 8)
                }
                .padding(.horizontal, 24)
                .opacity(contentOpacity)
                .offset(y: buttonOffset)
                
                Spacer().frame(height: 16)
                
                Text("Point your camera at furniture parts to begin")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.25))
                    .opacity(contentOpacity)
                
                Spacer().frame(height: 40)
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showAssembly) {
            AssemblyView()
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.1)) {
                logoScale = 1.0
                logoOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.4)) {
                contentOpacity = 1
                buttonOffset = 0
            }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                pulseRing = 1.08
            }
        }
    }
}

// MARK: - Status Row

private struct StatusRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let accentColor: Color
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(accentColor)
                .frame(width: 36, height: 36)
                .background(accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                
                Text(subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }
            
            Spacer()
            
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.06), lineWidth: 0.5)
                )
        }
    }
}

// MARK: - Grid Pattern

private struct GridPatternView: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 30
            for x in stride(from: 0, to: size.width, by: spacing) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.white), lineWidth: 0.5)
            }
            for y in stride(from: 0, to: size.height, by: spacing) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.white), lineWidth: 0.5)
            }
        }
    }
}

#Preview {
    HomeView()
}
