import RealityKit
import ARKit

class CPROverlay {
    
    // Creates two simple hands made of lines/boxes
    static func makeCPRHands() -> Entity {
        let root = Entity()
        
        // Left hand
        let leftHand = makeHand()
        leftHand.position = [-0.06, 0, 0]
        root.addChild(leftHand)
        
        // Right hand on top of left
        let rightHand = makeHand()
        rightHand.position = [-0.06, 0.02, 0]
        root.addChild(rightHand)
        
        // Add pump animation
        animatePump(entity: root)
        
        return root
    }
    
    // A hand made of simple white boxes — palm + 4 fingers
    static func makeHand() -> Entity {
        let hand = Entity()
        let material = SimpleMaterial(color: .white, isMetallic: false)
        
        // Palm
        let palm = ModelEntity(
            mesh: .generateBox(width: 0.08, height: 0.01, depth: 0.10),
            materials: [material]
        )
        hand.addChild(palm)
        
        // 4 fingers
        let fingerPositions: [Float] = [-0.03, -0.01, 0.01, 0.03]
        for x in fingerPositions {
            let finger = ModelEntity(
                mesh: .generateBox(width: 0.015, height: 0.01, depth: 0.04),
                materials: [material]
            )
            finger.position = [x, 0, -0.07]
            hand.addChild(finger)
        }
        
        // Thumb
        let thumb = ModelEntity(
            mesh: .generateBox(width: 0.04, height: 0.01, depth: 0.015),
            materials: [material]
        )
        thumb.position = [0.055, 0, 0.02]
        hand.addChild(thumb)
        
        return hand
    }
    
    // Pumping animation — moves up and down repeatedly
    static func animatePump(entity: Entity) {
        var downTransform = entity.transform
        downTransform.translation.y -= 0.05 // push down 5cm
        
        let pushDown = FromToByAnimation<Transform>(
            name: "pushDown",
            from: entity.transform,
            to: downTransform,
            duration: 0.4,
            timing: .easeInOut,
            bindTarget: .transform,
            repeatMode: .autoReverse
        )
        
        if let animation = try? AnimationResource.generate(with: pushDown) {
            entity.playAnimation(animation.repeat())
        }
    }
}