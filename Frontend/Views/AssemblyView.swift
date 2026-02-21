import SwiftUI
import RealityKit
import ARKit
import MWDATCore
import MWDATCamera

struct AssemblyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AssemblyViewModel()
    @State private var streamState: StreamSessionState = .stopped
    
    private var useGlassesFeed: Bool {
        streamState == .streaming
    }
    
    var body: some View {
        ZStack {
            #if canImport(ARKit) && canImport(UIKit)
            GlassesCameraView(streamStateChanged: { state in
                streamState = state
                if state == .streaming {
                    viewModel.isGlassesConnected = true
                    viewModel.cameraSource = .glasses
                }
            })
            .ignoresSafeArea()
            .opacity(useGlassesFeed ? 1 : 0)
            
            if !useGlassesFeed {
                ARCameraView()
                    .ignoresSafeArea()
            }
            #else
            Color.black.ignoresSafeArea()
            #endif
            
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
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }
}
