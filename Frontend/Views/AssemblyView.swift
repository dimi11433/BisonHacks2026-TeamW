import SwiftUI
#if canImport(UIKit)
import LiveKit
#endif

struct AssemblyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AssemblyViewModel()

    var body: some View {
        ZStack {
            // MARK: - Camera Background
            #if canImport(UIKit)
            if let track = viewModel.liveKit.localVideoTrack {
                SwiftUIVideoView(track, layoutMode: .fill)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                VStack(spacing: 12) {
                    if viewModel.liveKit.isConnecting {
                        ProgressView()
                            .tint(.white)
                        Text("Connecting...")
                            .foregroundStyle(.white)
                    } else if let error = viewModel.liveKit.connectionError {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(error)
                            .foregroundStyle(.white.opacity(0.7))
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Button("Retry") { viewModel.connectLiveKit() }
                            .buttonStyle(.bordered)
                            .tint(.white)
                    } else if viewModel.liveKit.isConnected {
                        ProgressView()
                            .tint(.white)
                        Text("Waiting for camera...")
                            .foregroundStyle(.white)
                    }
                }
            }
            #else
            Color.black.ignoresSafeArea()
            #endif

            // MARK: - Bounding Box Overlay
            BoundingBoxOverlay(boxes: viewModel.boundingBoxes)
                .ignoresSafeArea()

            // MARK: - CPR Step Overlay
            if viewModel.showCPROverlay {
                CPRAnimationOverlay(
                    instruction: viewModel.overlayInstruction,
                    onDismiss: { viewModel.dismissOverlay() }
                )
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(1)
            }

            // MARK: - HUD Layer
            VStack {
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

                    #if canImport(UIKit)
                    ConnectionPill(
                        isConnected: viewModel.liveKit.isConnected,
                        usingGlasses: viewModel.liveKit.usingGlasses
                    )
                    #endif
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
        .onAppear {
            viewModel.setupStepManager()
            Task {
                await viewModel.detectGlasses()
                viewModel.connectLiveKit()
            }
        }
        .onDisappear {
            viewModel.disconnectLiveKit()
        }
    }
}

// MARK: - Connection Indicator

private struct ConnectionPill: View {
    let isConnected: Bool
    var usingGlasses: Bool = false
    private let cyan = Color(hex: 0x00FFFF)

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isConnected ? Color.green : Color.orange)
                .frame(width: 6, height: 6)

            if isConnected {
                if usingGlasses {
                    Image(systemName: "eyeglasses")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Text(usingGlasses ? "Live \u{2022} Glasses" : "Live \u{2022} iPhone")
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                Text("Connecting")
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 0.5))
    }
}
