import SwiftUI
import RealityKit
import ARKit

struct AssemblyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AssemblyViewModel()
    
    var body: some View {
        ZStack {
            // MARK: - AR Camera Background
            #if canImport(ARKit) && canImport(UIKit)
            ARCameraView(isUsingGlasses: viewModel.isUsingGlasses)
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
                    // Back button
                    Button {
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
                    
                    ConnectionStatusView(isConnected: viewModel.isGlassesConnected)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                Spacer().frame(height: 16)
                
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
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }
}

// MARK: - Product Badge

private struct ProductBadge: View {
    @State private var appear = false
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color(hex: 0x00FFFF))
            
            VStack(alignment: .leading, spacing: 1) {
                Text("IKEA MALM")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text("Bed Frame Assembly")
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
