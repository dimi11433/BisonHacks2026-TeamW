import Foundation

struct AssemblyStep: Identifiable {
    let id: Int
    let title: String
    let instruction: String
    let icon: String
    let partsNeeded: [String]
    let estimatedMinutes: Int
}

enum VoiceTriggerState {
    case listening
    case responding
    
    var label: String {
        switch self {
        case .listening:  return "Listening"
        case .responding: return "Interrupt"
        }
    }
    
    var icon: String {
        switch self {
        case .listening:  return "stop.fill"
        case .responding: return "hand.raised.fill"
        }
    }
}

extension AssemblyStep {
    static let malmBedSteps: [AssemblyStep] = [
        AssemblyStep(
            id: 1,
            title: "Unpack & Sort Hardware",
            instruction: "Lay out all parts on the floor. Identify 4 side rails, 2 cross beams, headboard, and hardware bag.",
            icon: "shippingbox.fill",
            partsNeeded: ["Hardware bag", "Allen key", "Parts checklist"],
            estimatedMinutes: 5
        ),
        AssemblyStep(
            id: 2,
            title: "Assemble Headboard Frame",
            instruction: "Attach the two vertical posts to the headboard panel using cam locks. Hand-tighten only.",
            icon: "rectangle.portrait.and.arrow.right",
            partsNeeded: ["Headboard panel", "2x Vertical posts", "4x Cam locks"],
            estimatedMinutes: 8
        ),
        AssemblyStep(
            id: 3,
            title: "Attach Side Rails to Headboard",
            instruction: "Slide the left and right side rails into the headboard brackets. Secure with hex bolts.",
            icon: "arrow.left.and.right",
            partsNeeded: ["2x Side rails", "4x Hex bolts", "Allen key"],
            estimatedMinutes: 6
        ),
        AssemblyStep(
            id: 4,
            title: "Connect Footboard",
            instruction: "Align the footboard with both side rails. Insert dowels first, then lock cam bolts.",
            icon: "rectangle.bottomhalf.filled",
            partsNeeded: ["Footboard", "4x Dowels", "2x Cam bolts"],
            estimatedMinutes: 6
        ),
        AssemblyStep(
            id: 5,
            title: "Insert Dowels",
            instruction: "Press wooden dowels into the pre-drilled holes on the center beam. Align flush.",
            icon: "cylinder.fill",
            partsNeeded: ["8x Wooden dowels", "Center beam"],
            estimatedMinutes: 4
        ),
        AssemblyStep(
            id: 6,
            title: "Install Center Support Beam",
            instruction: "Place the center beam across the side rails. It should click into the metal brackets.",
            icon: "line.horizontal.3",
            partsNeeded: ["Center support beam", "2x Metal brackets"],
            estimatedMinutes: 5
        ),
        AssemblyStep(
            id: 7,
            title: "Place Slats & Final Check",
            instruction: "Lay all bed slats evenly across the frame. Tighten every bolt. Done!",
            icon: "checkmark.seal.fill",
            partsNeeded: ["Bed slats (qty varies)", "Allen key"],
            estimatedMinutes: 10
        )
    ]
}
