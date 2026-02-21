import SwiftUI
import RealityKit
import ARKit
import MWDATCore
import MWDATCamera

struct AssemblyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AssemblyViewModel()
    
    var body: some View {
        ZStack {
            // MARK: - Camera Background (auto-selected)
            #if canImport(ARKit) && canImport(UIKit)
            Group {
                if viewModel.cameraSource == .glasses {
                    GlassesCameraView()
                } else {
                    ARCameraView()
                }
            }
            .ignoresSafeArea()
            #else
            Color.black.ignoresSafeArea()
            #endif
            
            // MARK: - Minimal HUD
            VStack(spacing: 0) {
                
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
                    
                    ConnectionStatusView(
                        isConnected: viewModel.isGlassesConnected,
                        source: viewModel.cameraSource
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                Spacer()
                
                VoiceControlButton(
                    state: viewModel.voiceState,
                    waveformAmplitudes: viewModel.waveformAmplitudes,
                    onTap: { viewModel.toggleVoice() }
                )
                .padding(.bottom, 30)
            }
            
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

