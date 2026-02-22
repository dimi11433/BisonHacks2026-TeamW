import RealityKit
import ARKit

class ARViewController: UIViewController, ARSessionDelegate {
    
    var arView: ARView!
    var instructionLabel: UILabel!
    var currentAnchor: AnchorEntity?
    var bodyAnchor: AnchorEntity?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        arView = ARView(frame: view.bounds)
        arView.session.delegate = self
        view.addSubview(arView)
        
        instructionLabel = UILabel()
        instructionLabel.frame = CGRect(x: 20, y: 60, width: view.bounds.width - 40, height: 80)
        instructionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        instructionLabel.textColor = .white
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 2
        instructionLabel.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        instructionLabel.layer.cornerRadius = 12
        instructionLabel.clipsToBounds = true
        view.addSubview(instructionLabel)
        
        startAR()
        
        // TEMP TEST — remove before final demo
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.showStep(animation: "cpr_hands", instruction: "Place both hands on center of chest")
        }
    }
    
    func startAR() {
        guard ARBodyTrackingConfiguration.isSupported else {
            print("Body tracking not supported")
            return
        }
        let config = ARBodyTrackingConfiguration()
        arView.session.run(config)
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let bodyAnchorDetected = anchor as? ARBodyAnchor else { continue }
            let skeleton = bodyAnchorDetected.skeleton
            let jointNames = ARSkeletonDefinition.defaultBody3D.jointNames
            guard let index = jointNames.firstIndex(of: "spine_7_joint") else { continue }
            let chestTransform = skeleton.jointModelTransforms[index]
            bodyAnchor?.transform = Transform(matrix: bodyAnchorDetected.transform * chestTransform)
        }
    }
    
    func onStepReceived(animation: String, instruction: String) {
        DispatchQueue.main.async {
            self.showStep(animation: animation, instruction: instruction)
        }
    }
    
    private func showStep(animation: String, instruction: String) {
        print("🟢 showStep called: \(animation)")
        instructionLabel.text = instruction
        currentAnchor?.removeFromParent()
        
        let model = CPROverlay.makeCPRHands()
        let anchor = AnchorEntity(world: .zero)
        
        // Place 0.5m in front of camera
        if let cameraTransform = arView.session.currentFrame?.camera.transform {
            let forward = -simd_float3(
                cameraTransform.columns.2.x,
                cameraTransform.columns.2.y,
                cameraTransform.columns.2.z
            )
            anchor.position = simd_float3(
                cameraTransform.columns.3.x,
                cameraTransform.columns.3.y,
                cameraTransform.columns.3.z
            ) + forward * 0.5
        }
        
        anchor.addChild(model)
        arView.scene.addAnchor(anchor)
        currentAnchor = anchor
        bodyAnchor = anchor
        print("🟢 anchor placed")
    }
}