import SwiftUI
#if canImport(UIKit)
import LiveKit
import ARKit
#endif

struct AssemblyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AssemblyViewModel()
    var preferredCameraSource: CameraSource = .phone

    var body: some View {
        ZStack {
            // MARK: - Layer 0: Camera Background
            #if canImport(UIKit)
            if viewModel.liveKit.isConnected {
                if viewModel.liveKit.usingGlasses, let track = viewModel.liveKit.localVideoTrack {
                    ZStack {
                        SwiftUIVideoView(track, layoutMode: .fill)
                            .ignoresSafeArea()
                        OverlayRenderer(
                            overlays: viewModel.activeOverlays,
                            instruction: viewModel.overlayInstruction
                        )
                        .ignoresSafeArea()
                    }
                } else if let capturer = viewModel.arFrameCapturer {
                    ARSceneView(
                        overlays: viewModel.activeOverlays,
                        frameCapturer: capturer
                    )
                    .ignoresSafeArea()

                    if !viewModel.overlayInstruction.isEmpty {
                        VStack {
                            Spacer()
                            Text(viewModel.overlayInstruction)
                                .font(.system(.headline, design: .rounded, weight: .bold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                                .padding(.horizontal, 20)
                                .padding(.bottom, 120)
                        }
                        .allowsHitTesting(false)
                    }
                }
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

            // MARK: - Layer 1: Rich Animation Overlay
            if let anim = viewModel.activeAnimation {
                animationView(for: anim)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(1)
            }

            // MARK: - Layer 2: HUD Controls
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
                    SourceSwitcherPill(
                        isConnected: viewModel.liveKit.isConnected,
                        usingGlasses: viewModel.liveKit.usingGlasses,
                        glassesAvailable: viewModel.isGlassesConnected,
                        onSwitch: { source in viewModel.switchSource(to: source) }
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
            Task { await viewModel.detectGlasses() }
            viewModel.connectLiveKit(preferredSource: preferredCameraSource)
        }
        .onDisappear {
            viewModel.disconnectLiveKit()
        }
    }

    // MARK: - Animation Router

    @ViewBuilder
    private func animationView(for anim: AnimationCommand) -> some View {
        CPRAnimationOverlay(
            animationName: anim.animation,
            instruction: anim.instruction,
            onDismiss: { viewModel.dismissAnimation() },
            anchorX: anim.x,
            anchorY: anim.y
        )
    }
}

// MARK: - Source Switcher Pill

private struct SourceSwitcherPill: View {
    let isConnected: Bool
    var usingGlasses: Bool = false
    var glassesAvailable: Bool = false
    var onSwitch: (CameraSource) -> Void

    @State private var showingMenu = false

    private var currentSource: CameraSource { usingGlasses ? .glasses : .phone }

    var body: some View {
        Menu {
            Button {
                onSwitch(.phone)
            } label: {
                Label {
                    Text("iPhone Camera")
                } icon: {
                    Image(systemName: "iphone")
                }
            }
            .disabled(!usingGlasses)

            Button {
                onSwitch(.glasses)
            } label: {
                Label {
                    Text("Meta Ray-Ban")
                } icon: {
                    Image(systemName: "eyeglasses")
                }
            }
            .disabled(usingGlasses || !glassesAvailable)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(isConnected ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)

                if isConnected {
                    Image(systemName: currentSource.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    Text("Live \u{2022} \(currentSource.rawValue)")
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
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
        .menuStyle(.borderlessButton)
        .disabled(!isConnected)
    }
}
