#if canImport(UIKit)
import SwiftUI
import RealityKit
import ARKit

/// Wraps an ARView with world tracking. Bounding boxes from the AI are raycasted
/// into 3D world space and placed as anchored entities so they track with the scene.
struct ARSceneView: UIViewRepresentable {

    let boxes: [BoundingBox]
    let frameCapturer: ARFrameCapturer

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        arView.session.run(config)
        arView.renderOptions.insert(.disableMotionBlur)

        arView.session.delegate = frameCapturer
        context.coordinator.arView = arView

        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        let coordinator = context.coordinator
        let currentIDs = Set(boxes.map(\.id))
        let previousIDs = Set(coordinator.placedBoxIDs)

        if currentIDs.isEmpty && !previousIDs.isEmpty {
            coordinator.clearAllBoxes(in: arView)
            return
        }

        let newIDs = currentIDs.subtracting(previousIDs)
        let removedIDs = previousIDs.subtracting(currentIDs)

        for id in removedIDs {
            coordinator.removeBox(id: id, from: arView)
        }

        for box in boxes where newIDs.contains(box.id) {
            coordinator.placeBox(box, in: arView)
        }
    }

    // MARK: - Coordinator

    class Coordinator {
        weak var arView: ARView?
        private var anchors: [String: AnchorEntity] = [:]
        var placedBoxIDs: [String] { Array(anchors.keys) }

        private let cyan = UIColor(red: 0, green: 1, blue: 1, alpha: 1)

        func placeBox(_ box: BoundingBox, in arView: ARView) {
            let bounds = arView.bounds
            guard bounds.width > 0, bounds.height > 0 else { return }

            let centerX = CGFloat((box.x_min + box.x_max) / 2) * bounds.width
            let centerY = CGFloat((box.y_min + box.y_max) / 2) * bounds.height
            let screenPoint = CGPoint(x: centerX, y: centerY)

            let worldPosition: SIMD3<Float>
            let anchorOrientation: simd_quatf
            let estimatedDepth: Float = 1.2

            let raycastResults = arView.raycast(
                from: screenPoint,
                allowing: .estimatedPlane,
                alignment: .any
            )
            if let hit = raycastResults.first {
                worldPosition = SIMD3<Float>(
                    hit.worldTransform.columns.3.x,
                    hit.worldTransform.columns.3.y,
                    hit.worldTransform.columns.3.z
                )
                let surfaceNormal = SIMD3<Float>(
                    hit.worldTransform.columns.1.x,
                    hit.worldTransform.columns.1.y,
                    hit.worldTransform.columns.1.z
                )
                anchorOrientation = Self.orientationForNormal(
                    surfaceNormal, arView: arView
                )
            } else if let ray = arView.ray(through: screenPoint) {
                worldPosition = ray.origin + ray.direction * estimatedDepth
                anchorOrientation = Self.orientationForNormal(
                    normalize(-(ray.direction)), arView: arView
                )
            } else {
                guard let frame = arView.session.currentFrame else { return }
                let camTransform = frame.camera.transform
                let forward = -SIMD3<Float>(
                    camTransform.columns.2.x,
                    camTransform.columns.2.y,
                    camTransform.columns.2.z
                )
                let camPos = SIMD3<Float>(
                    camTransform.columns.3.x,
                    camTransform.columns.3.y,
                    camTransform.columns.3.z
                )
                let pos = camPos + forward * estimatedDepth
                worldPosition = pos
                anchorOrientation = Self.orientationForNormal(
                    normalize(-forward), arView: arView
                )
            }

            let boxWidth = Float(box.width) * estimatedDepth
            let boxHeight = Float(box.height) * estimatedDepth
            let thickness: Float = 0.001

            let anchor = AnchorEntity(world: worldPosition)
            anchor.orientation = anchorOrientation

            let edgeRadius: Float = 0.002
            let edgeMaterial = UnlitMaterial(color: cyan)

            // All edges in the XY plane (anchor's local facing plane, +Z = outward)
            let topBar = ModelEntity(
                mesh: .generateBox(size: SIMD3(boxWidth, edgeRadius, edgeRadius), cornerRadius: edgeRadius / 2),
                materials: [edgeMaterial]
            )
            topBar.position = SIMD3(0, boxHeight / 2, 0)

            let bottomBar = ModelEntity(
                mesh: .generateBox(size: SIMD3(boxWidth, edgeRadius, edgeRadius), cornerRadius: edgeRadius / 2),
                materials: [edgeMaterial]
            )
            bottomBar.position = SIMD3(0, -boxHeight / 2, 0)

            let leftBar = ModelEntity(
                mesh: .generateBox(size: SIMD3(edgeRadius, boxHeight, edgeRadius), cornerRadius: edgeRadius / 2),
                materials: [edgeMaterial]
            )
            leftBar.position = SIMD3(-boxWidth / 2, 0, 0)

            let rightBar = ModelEntity(
                mesh: .generateBox(size: SIMD3(edgeRadius, boxHeight, edgeRadius), cornerRadius: edgeRadius / 2),
                materials: [edgeMaterial]
            )
            rightBar.position = SIMD3(boxWidth / 2, 0, 0)

            let labelMesh = MeshResource.generateText(
                box.label,
                extrusionDepth: thickness,
                font: .systemFont(ofSize: 0.04, weight: .bold),
                containerFrame: .zero,
                alignment: .center,
                lineBreakMode: .byTruncatingTail
            )
            let labelEntity = ModelEntity(mesh: labelMesh, materials: [edgeMaterial])
            let labelWidth = labelMesh.bounds.extents.x
            labelEntity.position = SIMD3(
                -labelWidth / 2,
                boxHeight / 2 + 0.02,
                0
            )

            anchor.addChild(topBar)
            anchor.addChild(bottomBar)
            anchor.addChild(leftBar)
            anchor.addChild(rightBar)
            anchor.addChild(labelEntity)

            arView.scene.addAnchor(anchor)
            anchors[box.id] = anchor
        }

        func removeBox(id: String, from arView: ARView) {
            if let anchor = anchors.removeValue(forKey: id) {
                arView.scene.removeAnchor(anchor)
            }
        }

        func clearAllBoxes(in arView: ARView) {
            for anchor in anchors.values {
                arView.scene.removeAnchor(anchor)
            }
            anchors.removeAll()
        }

        /// Build a right-handed orientation from a surface normal so that:
        ///   - local +Z = normal direction (box faces outward from surface)
        ///   - local +Y = as close to world-up as possible (text right-side-up)
        ///   - local +X = right (text reads left-to-right, never mirrored)
        /// For near-vertical normals (floors/ceilings), uses camera forward
        /// projected onto the surface to determine the "up" for text readability.
        private static func orientationForNormal(
            _ normal: SIMD3<Float>,
            arView: ARView
        ) -> simd_quatf {
            let forward = normalize(normal)
            let worldUp = SIMD3<Float>(0, 1, 0)

            let right: SIMD3<Float>
            let up: SIMD3<Float>

            if abs(dot(forward, worldUp)) > 0.95 {
                // Normal is nearly vertical (floor / ceiling).
                // Use camera forward projected onto the surface plane to pick
                // an "up" direction that keeps text readable from the viewer.
                guard let frame = arView.session.currentFrame else {
                    return simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
                }
                let camFwd = -SIMD3<Float>(
                    frame.camera.transform.columns.2.x,
                    frame.camera.transform.columns.2.y,
                    frame.camera.transform.columns.2.z
                )
                let projected = camFwd - dot(camFwd, forward) * forward
                if length(projected) > 1e-6 {
                    up = normalize(projected)
                } else {
                    up = SIMD3<Float>(0, 0, -1)
                }
                right = normalize(cross(up, forward))
            } else {
                // Normal is mostly horizontal (walls, angled surfaces).
                right = normalize(cross(worldUp, forward))
                up = cross(forward, right)
            }

            let m = simd_float3x3(columns: (right, up, forward))
            return simd_quatf(m)
        }
    }
}

#endif
