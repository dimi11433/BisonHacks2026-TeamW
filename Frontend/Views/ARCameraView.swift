#if canImport(ARKit) && canImport(RealityKit) && canImport(UIKit)
import SwiftUI
import RealityKit
import ARKit
import MWDATCore
import MWDATCamera

// MARK: - Phone AR Camera

struct ARCameraView: UIViewRepresentable {
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.environment.background = .cameraFeed()
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        arView.session.run(config)
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}

// MARK: - Glasses Camera (Meta Ray-Ban stream)

struct GlassesCameraView: UIViewRepresentable {
    var streamStateChanged: ((StreamSessionState) -> Void)?
    
    final class Coordinator {
        var streamSession: StreamSession?
        var frameToken: (any AnyListenerToken)?
        var stateToken: (any AnyListenerToken)?
        var onStateChange: ((StreamSessionState) -> Void)?
    }
    
    func makeCoordinator() -> Coordinator {
        let c = Coordinator()
        c.onStateChange = streamStateChanged
        return c
    }
    
    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .clear
        
        Task { @MainActor in
            await startStream(imageView: imageView, coordinator: context.coordinator)
        }
        
        return imageView
    }
    
    func updateUIView(_ uiView: UIImageView, context: Context) {}
    
    @MainActor
    private func startStream(imageView: UIImageView, coordinator: Coordinator) async {
        let wearables = Wearables.shared
        print("[GlassesCam] Starting stream. reg=\(wearables.registrationState), devices=\(wearables.devices)")
        
        // Try registration if not registered
        if wearables.registrationState != .registered {
            print("[GlassesCam] Attempting registration...")
            do throws(RegistrationError) {
                try await wearables.startRegistration()
                print("[GlassesCam] Registration done. reg=\(wearables.registrationState)")
            } catch {
                print("[GlassesCam] Registration error: \(error) — proceeding anyway")
            }
        }
        
        let selector = AutoDeviceSelector(wearables: wearables)
        print("[GlassesCam] AutoDeviceSelector active device: \(selector.activeDevice ?? "none")")
        
        let config = StreamSessionConfig(
            videoCodec: .raw,
            resolution: .medium,
            frameRate: 24
        )
        let session = StreamSession(streamSessionConfig: config, deviceSelector: selector)
        coordinator.streamSession = session
        
        coordinator.frameToken = session.videoFramePublisher.listen { frame in
            if let image = frame.makeUIImage() {
                Task { @MainActor in
                    imageView.image = image
                }
            }
        }
        
        coordinator.stateToken = session.statePublisher.listen { state in
            print("[GlassesCam] Stream state: \(state)")
            Task { @MainActor in
                coordinator.onStateChange?(state)
            }
        }
        
        print("[GlassesCam] Calling session.start()...")
        await session.start()
        print("[GlassesCam] session.start() returned. state=\(session.state)")
    }
    
    static func dismantleUIView(_ uiView: UIImageView, coordinator: Coordinator) {
        Task { @MainActor in
            await coordinator.streamSession?.stop()
        }
        Task {
            await coordinator.frameToken?.cancel()
            await coordinator.stateToken?.cancel()
        }
        coordinator.streamSession = nil
    }
}
#endif
