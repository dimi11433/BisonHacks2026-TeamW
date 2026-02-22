#if canImport(UIKit)
import SwiftUI
import RealityKit
import ARKit

struct ARSceneView: UIViewRepresentable {

    let overlays: [OverlayCommand]
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
        let currentIDs = Set(overlays.map(\.id))
        let previousIDs = Set(coordinator.placedIDs)

        if currentIDs.isEmpty && !previousIDs.isEmpty {
            coordinator.clearAll(in: arView)
            return
        }

        let newIDs = currentIDs.subtracting(previousIDs)
        let removedIDs = previousIDs.subtracting(currentIDs)

        for id in removedIDs {
            coordinator.removeOverlay(id: id, from: arView)
        }

        for cmd in overlays where newIDs.contains(cmd.id) {
            coordinator.placeOverlay(cmd, in: arView)
        }
    }

    // MARK: - Coordinator

    class Coordinator {
        weak var arView: ARView?
        private var anchors: [String: AnchorEntity] = [:]
        var placedIDs: [String] { Array(anchors.keys) }

        // MARK: Place Overlay

        func placeOverlay(_ cmd: OverlayCommand, in arView: ARView) {
            switch cmd.type {
            case .icon:
                placeIcon(cmd, in: arView)
            case .circle:
                placeCircle(cmd, in: arView)
            case .region:
                placeRegion(cmd, in: arView)
            case .arrow:
                placeArrow(cmd, in: arView)
            case .label:
                placeLabel(cmd, in: arView)
            }
        }

        // MARK: Icon — textured plane with SF Symbol

        private func placeIcon(_ cmd: OverlayCommand, in arView: ARView) {
            let screenPoint = screenPoint(x: cmd.x ?? 0.5, y: cmd.y ?? 0.5, in: arView)
            guard let (worldPos, orientation) = resolve3DPosition(
                screenPoint: screenPoint, in: arView
            ) else { return }

            let anchor = AnchorEntity(world: worldPos)
            anchor.orientation = orientation

            let iconSize: Float = 0.08 * Float(cmd.resolvedScale)

            if let texture = sfSymbolTexture(
                name: cmd.asset ?? "questionmark.circle",
                color: cmd.resolvedColor,
                pointSize: 120
            ) {
                var material = UnlitMaterial()
                material.color = .init(tint: .white, texture: .init(texture))
                material.blending = .transparent(opacity: 1.0)

                let plane = ModelEntity(
                    mesh: .generatePlane(width: iconSize, height: iconSize),
                    materials: [material]
                )
                anchor.addChild(plane)
            }

            if let label = cmd.label {
                let labelEntity = makeTextEntity(
                    label, color: uiColor(from: cmd), size: 0.03
                )
                labelEntity.position = SIMD3(0, -(iconSize / 2 + 0.02), 0)
                anchor.addChild(labelEntity)
            }

            arView.scene.addAnchor(anchor)
            anchors[cmd.id] = anchor
        }

        // MARK: Circle — torus ring

        private func placeCircle(_ cmd: OverlayCommand, in arView: ARView) {
            let screenPoint = screenPoint(x: cmd.x ?? 0.5, y: cmd.y ?? 0.5, in: arView)
            guard let (worldPos, orientation) = resolve3DPosition(
                screenPoint: screenPoint, in: arView
            ) else { return }

            let anchor = AnchorEntity(world: worldPos)
            anchor.orientation = orientation

            let worldRadius: Float = Float(cmd.resolvedRadius) * 1.2
            let ringThickness: Float = 0.004
            let color = uiColor(from: cmd)

            let ring = ModelEntity(
                mesh: .generateBox(
                    size: SIMD3(worldRadius * 2, ringThickness, ringThickness),
                    cornerRadius: ringThickness / 2
                ),
                materials: [UnlitMaterial(color: color)]
            )

            let segments = 32
            for i in 0..<segments {
                let angle = Float(i) / Float(segments) * 2 * .pi
                let segX = worldRadius * cos(angle)
                let segY = worldRadius * sin(angle)

                let dot = ModelEntity(
                    mesh: .generateSphere(radius: ringThickness),
                    materials: [UnlitMaterial(color: color)]
                )
                dot.position = SIMD3(segX, segY, 0)
                anchor.addChild(dot)
            }

            _ = ring

            if let label = cmd.label {
                let labelEntity = makeTextEntity(
                    label, color: color, size: 0.025
                )
                labelEntity.position = SIMD3(0, -(worldRadius + 0.025), 0)
                anchor.addChild(labelEntity)
            }

            arView.scene.addAnchor(anchor)
            anchors[cmd.id] = anchor
        }

        // MARK: Region — wireframe box (same as old bounding box)

        private func placeRegion(_ cmd: OverlayCommand, in arView: ARView) {
            let cx = ((cmd.x_min ?? 0) + (cmd.x_max ?? 0)) / 2
            let cy = ((cmd.y_min ?? 0) + (cmd.y_max ?? 0)) / 2
            let screenPt = screenPoint(x: cx, y: cy, in: arView)

            guard let (worldPos, orientation) = resolve3DPosition(
                screenPoint: screenPt, in: arView
            ) else { return }

            let estimatedDepth: Float = 1.2
            let boxWidth = Float((cmd.x_max ?? 0) - (cmd.x_min ?? 0)) * estimatedDepth
            let boxHeight = Float((cmd.y_max ?? 0) - (cmd.y_min ?? 0)) * estimatedDepth
            let edgeRadius: Float = 0.002
            let color = uiColor(from: cmd)
            let edgeMaterial = UnlitMaterial(color: color)

            let anchor = AnchorEntity(world: worldPos)
            anchor.orientation = orientation

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

            anchor.addChild(topBar)
            anchor.addChild(bottomBar)
            anchor.addChild(leftBar)
            anchor.addChild(rightBar)

            if let label = cmd.label {
                let labelEntity = makeTextEntity(
                    label, color: color, size: 0.04
                )
                let labelWidth = labelEntity.model?.mesh.bounds.extents.x ?? 0
                labelEntity.position = SIMD3(
                    -labelWidth / 2,
                    boxHeight / 2 + 0.02,
                    0
                )
                anchor.addChild(labelEntity)
            }

            arView.scene.addAnchor(anchor)
            anchors[cmd.id] = anchor
        }

        // MARK: Arrow — cylinder between two 3D points

        private func placeArrow(_ cmd: OverlayCommand, in arView: ARView) {
            let fromScreen = screenPoint(
                x: cmd.from_x ?? 0, y: cmd.from_y ?? 0, in: arView
            )
            let toScreen = screenPoint(
                x: cmd.to_x ?? 0, y: cmd.to_y ?? 0, in: arView
            )

            guard let (fromPos, _) = resolve3DPosition(
                screenPoint: fromScreen, in: arView
            ) else { return }
            guard let (toPos, _) = resolve3DPosition(
                screenPoint: toScreen, in: arView
            ) else { return }

            let color = uiColor(from: cmd)
            let anchor = AnchorEntity(world: fromPos)

            let direction = toPos - fromPos
            let distance = length(direction)
            guard distance > 0.001 else { return }

            let shaftRadius: Float = 0.003
            let shaft = ModelEntity(
                mesh: .generateBox(
                    size: SIMD3(shaftRadius * 2, distance, shaftRadius * 2),
                    cornerRadius: shaftRadius
                ),
                materials: [UnlitMaterial(color: color)]
            )

            let midpoint = direction / 2
            shaft.position = midpoint

            let up = SIMD3<Float>(0, 1, 0)
            let dir = normalize(direction)
            let dotProduct = dot(up, dir)
            if abs(dotProduct) < 0.999 {
                let axis = normalize(cross(up, dir))
                let angle = acos(dotProduct)
                shaft.orientation = simd_quatf(angle: angle, axis: axis)
            }

            let headSize: Float = 0.012
            let head = ModelEntity(
                mesh: .generateBox(size: SIMD3(headSize, headSize, headSize)),
                materials: [UnlitMaterial(color: color)]
            )
            head.position = direction

            anchor.addChild(shaft)
            anchor.addChild(head)

            arView.scene.addAnchor(anchor)
            anchors[cmd.id] = anchor
        }

        // MARK: Label — 3D floating text

        private func placeLabel(_ cmd: OverlayCommand, in arView: ARView) {
            let screenPt = screenPoint(x: cmd.x ?? 0.5, y: cmd.y ?? 0.5, in: arView)
            guard let (worldPos, orientation) = resolve3DPosition(
                screenPoint: screenPt, in: arView
            ) else { return }

            let color = uiColor(from: cmd)
            let anchor = AnchorEntity(world: worldPos)
            anchor.orientation = orientation

            if let text = cmd.label {
                let entity = makeTextEntity(text, color: color, size: 0.04)
                let textWidth = entity.model?.mesh.bounds.extents.x ?? 0
                entity.position = SIMD3(-textWidth / 2, 0, 0)
                anchor.addChild(entity)
            }

            arView.scene.addAnchor(anchor)
            anchors[cmd.id] = anchor
        }

        // MARK: Removal

        func removeOverlay(id: String, from arView: ARView) {
            if let anchor = anchors.removeValue(forKey: id) {
                arView.scene.removeAnchor(anchor)
            }
        }

        func clearAll(in arView: ARView) {
            for anchor in anchors.values {
                arView.scene.removeAnchor(anchor)
            }
            anchors.removeAll()
        }

        // MARK: - Helpers

        private func screenPoint(x: Double, y: Double, in arView: ARView) -> CGPoint {
            let bounds = arView.bounds
            return CGPoint(
                x: CGFloat(x) * bounds.width,
                y: CGFloat(y) * bounds.height
            )
        }

        private func resolve3DPosition(
            screenPoint: CGPoint,
            in arView: ARView
        ) -> (SIMD3<Float>, simd_quatf)? {
            let bounds = arView.bounds
            guard bounds.width > 0, bounds.height > 0 else { return nil }

            let estimatedDepth: Float = 1.2

            let raycastResults = arView.raycast(
                from: screenPoint,
                allowing: .estimatedPlane,
                alignment: .any
            )

            if let hit = raycastResults.first {
                let pos = SIMD3<Float>(
                    hit.worldTransform.columns.3.x,
                    hit.worldTransform.columns.3.y,
                    hit.worldTransform.columns.3.z
                )
                let normal = SIMD3<Float>(
                    hit.worldTransform.columns.1.x,
                    hit.worldTransform.columns.1.y,
                    hit.worldTransform.columns.1.z
                )
                return (pos, Self.orientationForNormal(normal, arView: arView))
            }

            if let ray = arView.ray(through: screenPoint) {
                let pos = ray.origin + ray.direction * estimatedDepth
                let orientation = Self.orientationForNormal(
                    normalize(-(ray.direction)), arView: arView
                )
                return (pos, orientation)
            }

            guard let frame = arView.session.currentFrame else { return nil }
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
            return (pos, Self.orientationForNormal(normalize(-forward), arView: arView))
        }

        private func sfSymbolTexture(
            name: String,
            color: Color,
            pointSize: CGFloat
        ) -> TextureResource? {
            let config = UIImage.SymbolConfiguration(
                pointSize: pointSize, weight: .bold
            )
            guard let image = UIImage(systemName: name, withConfiguration: config)?
                .withTintColor(UIColor(color), renderingMode: .alwaysOriginal)
            else { return nil }

            let size = CGSize(width: 256, height: 256)
            let renderer = UIGraphicsImageRenderer(size: size)
            let rendered = renderer.image { ctx in
                UIColor.clear.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                let imageSize = image.size
                let scale = min(size.width / imageSize.width, size.height / imageSize.height) * 0.8
                let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
                let origin = CGPoint(
                    x: (size.width - drawSize.width) / 2,
                    y: (size.height - drawSize.height) / 2
                )
                image.draw(in: CGRect(origin: origin, size: drawSize))
            }

            guard let cgImage = rendered.cgImage else { return nil }
            return try? TextureResource.generate(
                from: cgImage,
                options: .init(semantic: .color)
            )
        }

        private func makeTextEntity(
            _ text: String,
            color: UIColor,
            size: CGFloat
        ) -> ModelEntity {
            let mesh = MeshResource.generateText(
                text,
                extrusionDepth: 0.001,
                font: .systemFont(ofSize: size, weight: .bold),
                containerFrame: .zero,
                alignment: .center,
                lineBreakMode: .byTruncatingTail
            )
            return ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)])
        }

        private func uiColor(from cmd: OverlayCommand) -> UIColor {
            UIColor(cmd.resolvedColor)
        }

        private static func orientationForNormal(
            _ normal: SIMD3<Float>,
            arView: ARView
        ) -> simd_quatf {
            let forward = normalize(normal)
            let worldUp = SIMD3<Float>(0, 1, 0)

            let right: SIMD3<Float>
            let up: SIMD3<Float>

            if abs(dot(forward, worldUp)) > 0.95 {
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
                right = normalize(cross(worldUp, forward))
                up = cross(forward, right)
            }

            let m = simd_float3x3(columns: (right, up, forward))
            return simd_quatf(m)
        }
    }
}

#endif
