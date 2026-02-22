import RealityKit
import ARKit

class ARViewController: UIViewController, ARSessionDelegate {
    
    var arView: ARView!
    var instructionLabel: UILabel!
    var currentAnchor: AnchorEntity?
    var bodyAnchor: AnchorEntity?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set up AR view
        arView = ARView(frame: view.bounds)
        arView.session.delegate = self
        view.addSubview(arView)
        
        // Instruction label at top
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
            self.onStepReceived(animation: "cpr_hands", instruction: "Place both hands on center of chest")
        }
    }
    
    func startAR() {
        guard ARBodyTrackingConfiguration.isSupported else {
            print("Body tracking not supported on this device")
            return
        }
        let config = ARBodyTrackingConfiguration()
        arView.session.run(config)
    }
    
    // ARSessionDelegate — fires every frame
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let bodyAnchorDetected = anchor as? ARBodyAnchor else { continue }
            
            // Get the chest joint transform
            let skeleton = bodyAnchorDetected.skeleton
            let jointNames = ARSkeletonDefinition.defaultBody3D.jointNames
            guard let index = jointNames.firstIndex(of: "spine_7_joint") else { continue }
            
            let chestTransform = skeleton.jointModelTransforms[index]
            bodyAnchor?.transform = Transform(matrix: bodyAnchorDetected.transform * chestTransform)
        }
    }
    
    // Call this when JSON arrives from LiveKit
    func onStepReceived(animation: String, instruction: String) {
        DispatchQueue.main.async {
            self.instructionLabel.text = instruction
            self.currentAnchor?.removeFromParent()
            
            let model = CPROverlay.makeCPRHands()
            
            let anchor = AnchorEntity(world: .zero)
            anchor.addChild(model)
            self.arView.scene.addAnchor(anchor)
            self.currentAnchor = anchor
            self.bodyAnchor = anchor
        }
    }
}