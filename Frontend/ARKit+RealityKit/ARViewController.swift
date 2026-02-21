import RealityKit
import ARKit
import LiveKit

class ARViewController: UIViewController {
    
    var arView: ARView!
    var instructionLabel: UILabel!
    var currentAnchor: AnchorEntity?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set up AR view
        arView = ARView(frame: view.bounds)
        view.addSubview(arView)
        
        // Set up instruction label overlay
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
        
        // Start AR session with hand tracking
        startAR()
    }
    
    func startAR() {
        guard ARBodyTrackingConfiguration.isSupported else {
            print("Body tracking not supported")
            return
        }
        let config = ARBodyTrackingConfiguration()
        arView.session.run(config)
    }
    
    // Call this when JSON arrives from LiveKit
    func onStepReceived(animation: String, instruction: String) {
        DispatchQueue.main.async {
            // Update instruction text
            self.instructionLabel.text = instruction
            
            // Remove previous animation
            self.currentAnchor?.removeFromParent()
            
            // Load and place new animation anchored to left forearm
            if let model = try? Entity.load(named: animation) {
                let anchor = AnchorEntity(.bodyPosition(.leftForearm))
                anchor.addChild(model)
                self.arView.scene.addAnchor(anchor)
                self.currentAnchor = anchor
            } else {
                print("Could not load \(animation).usdz")
            }
        }
    }
}