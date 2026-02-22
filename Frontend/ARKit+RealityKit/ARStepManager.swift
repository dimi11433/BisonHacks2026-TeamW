import Foundation

@MainActor
class ARStepManager {
    static let shared = ARStepManager()
    var onStep: ((String, String) -> Void)?
    
    func trigger(animation: String, instruction: String) {
        onStep?(animation, instruction)
    }
}