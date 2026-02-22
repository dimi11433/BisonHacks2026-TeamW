import Foundation

@MainActor
class ARStepManager {
    static let shared = ARStepManager()
    var onStep: ((String, String) -> Void)?
    
    func trigger(animation: String, instruction: String) {
        print("[AR] ARStepManager.trigger — animation: \(animation), hasCallback: \(onStep != nil)")
        onStep?(animation, instruction)
    }
}