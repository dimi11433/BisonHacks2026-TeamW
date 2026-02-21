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
        
        addGhostAnchor(to: arView)
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
    
    private func addGhostAnchor(to arView: ARView) {
        let mesh = MeshResource.generateBox(
            size: [0.15, 0.02, 0.25],
            cornerRadius: 0.005
        )
        
        var material = SimpleMaterial()
        material.color = .init(
            tint: UIColor.cyan.withAlphaComponent(0.15),
            texture: nil
        )
        material.metallic = .float(0.8)
        material.roughness = .float(0.2)
        
        let model = ModelEntity(mesh: mesh, materials: [material])
        model.position = SIMD3(0, 0, -0.5)
        
        let anchor = AnchorEntity(plane: .horizontal,
                                  minimumBounds: [0.2, 0.2])
        anchor.addChild(model)
        arView.scene.addAnchor(anchor)
    }
}

// MARK: - Glasses Camera (Meta Ray-Ban stream)

struct GlassesCameraView: UIViewRepresentable {
    
    final class Coordinator {
        var streamSession: StreamSession?
        var frameToken: (any AnyListenerToken)?
        var stateToken: (any AnyListenerToken)?
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .black
        
        Task { @MainActor in
            await startStream(imageView: imageView, coordinator: context.coordinator)
        }
        
        return imageView
    }
    
    func updateUIView(_ uiView: UIImageView, context: Context) {}
    
    @MainActor
    private func startStream(imageView: UIImageView, coordinator: Coordinator) async {
        let selector = AutoDeviceSelector(wearables: Wearables.shared)
        let session = StreamSession(deviceSelector: selector)
        coordinator.streamSession = session
        
        coordinator.frameToken = session.videoFramePublisher.listen { frame in
            if let image = frame.makeUIImage() {
                Task { @MainActor in
                    imageView.image = image
                }
            }
        }
        
        coordinator.stateToken = session.statePublisher.listen { state in
            print("[GlassesCameraView] Stream state: \(state)")
        }
        
        await session.start()
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
