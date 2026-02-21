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

            // MARK: - HUD Layer
            VStack {
                // Top bar — close button only
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
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

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
        .onAppear {
            viewModel.detectGlasses()
        }
    }
}
