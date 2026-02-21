#if canImport(ARKit) && canImport(RealityKit) && canImport(UIKit)
import SwiftUI
import RealityKit
import ARKit

struct ARCameraView: UIViewRepresentable {
    let isUsingGlasses: Bool
    
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
#endif
