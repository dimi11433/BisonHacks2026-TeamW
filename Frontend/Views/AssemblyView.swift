import SwiftUI
import RealityKit
import ARKit

struct AssemblyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AssemblyViewModel()
    
    var body: some View {
        ZStack {
            // MARK: - Camera Background (auto-selected)
            #if canImport(ARKit) && canImport(UIKit)
            ARCameraView(isUsingGlasses: viewModel.cameraSource == .glasses)
                .ignoresSafeArea()
            #else
            Color.black.ignoresSafeArea()
            #endif
            
            // Dim overlay for contrast
            LinearGradient(
                colors: [
                    .black.opacity(0.5),
                    .clear,
                    .clear,
                    .black.opacity(0.6)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            
            // MARK: - Ghost Part Bounding Box
            GhostPartOverlay(isVisible: true)
            
            // MARK: - HUD Layer
            VStack(spacing: 0) {
                
                // Top bar
                HStack {
                    Button {
                        viewModel.cleanup()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 0.5))
                    }
                    
                    Spacer()
                    
                    ProductBadge()
                    
                    Spacer()
                    
                    ConnectionStatusView(
                        isConnected: viewModel.isGlassesConnected,
                        source: viewModel.cameraSource
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                // Camera source indicator
                CameraSourceBanner(source: viewModel.cameraSource)
                    .padding(.top, 8)
                
                Spacer().frame(height: 12)
                
                // Glassmorphism instruction card
                GlassmorphismHUD(
                    step: viewModel.currentStep,
                    totalSteps: viewModel.totalSteps,
                    progress: viewModel.progress,
                    onNext: { viewModel.nextStep() },
                    onPrevious: { viewModel.previousStep() }
                )
                
                Spacer()
                
                // Voice control at bottom
                VoiceControlButton(
                    state: viewModel.voiceState,
                    waveformAmplitudes: viewModel.waveformAmplitudes,
                    onTap: { viewModel.toggleVoice() }
                )
                .padding(.bottom, 30)
            }
            
            // Detection overlay
            if viewModel.isDetectingGlasses {
                DetectingOverlay()
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onAppear {
            viewModel.detectGlasses()
        }
    }
}

// MARK: - Camera Source Banner

private struct CameraSourceBanner: View {
    let source: CameraSource
    @State private var appear = false
    
    private let cyan = Color(hex: 0x00FFFF)
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: source.icon)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
            
            Text("Using \(source.rawValue)")
                .font(.system(.caption2, design: .rounded, weight: .medium))
        }
        .foregroundStyle(source == .glasses ? cyan : .white.opacity(0.6))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(source == .glasses ? cyan.opacity(0.12) : .white.opacity(0.06))
                .overlay(
                    Capsule()
                        .stroke(source == .glasses ? cyan.opacity(0.25) : .white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .opacity(appear ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.5)) {
                appear = true
            }
        }
        .animation(.easeInOut(duration: 0.3), value: source)
    }
}

// MARK: - Detecting Overlay

private struct DetectingOverlay: View {
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            
            VStack(spacing: 16) {
                Image(systemName: "eyeglasses")
                    .font(.system(size: 40, weight: .light, design: .rounded))
                    .foregroundStyle(Color(hex: 0x00FFFF))
                    .rotationEffect(.degrees(rotation))
                
                Text("Detecting glasses...")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
        }
    }
}

// MARK: - Product Badge

private struct ProductBadge: View {
    @State private var appear = false
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color(hex: 0x00FFFF))
            
            VStack(alignment: .leading, spacing: 1) {
                Text("SPATIAL ASSIST")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text("Ask me anything")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
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
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : -10)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3)) {
                appear = true
            }
        }
    }
}
