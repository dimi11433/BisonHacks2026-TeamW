import SwiftUI

// MARK: - Overlay Primitive Types

enum OverlayType: String, Codable, Sendable {
    case icon
    case arrow
    case circle
    case region
    case label
}

// MARK: - Overlay Command

struct OverlayCommand: Identifiable, Codable, Sendable {
    let type: OverlayType

    // Shared position (icon, circle, label)
    let x: Double?
    let y: Double?

    // Icon-specific
    let asset: String?
    let scale: Double?
    let pulse: Bool?

    // Arrow endpoints
    let from_x: Double?
    let from_y: Double?
    let to_x: Double?
    let to_y: Double?

    // Region bounds
    let x_min: Double?
    let y_min: Double?
    let x_max: Double?
    let y_max: Double?

    // Circle-specific
    let radius: Double?

    // Shared visual properties
    let color: String?
    let label: String?
    let style: String?

    var id: String {
        let pos = "\(x ?? from_x ?? x_min ?? 0)-\(y ?? from_y ?? y_min ?? 0)"
        return "\(type.rawValue)-\(pos)-\(asset ?? label ?? "")"
    }

    var resolvedColor: Color {
        guard let hex = color else { return Color(hex: 0x00FFFF) }
        return Color(hexString: hex)
    }

    var resolvedScale: Double { scale ?? 1.0 }
    var resolvedRadius: Double { radius ?? 0.05 }
    var shouldPulse: Bool { pulse ?? false }
}

// MARK: - Overlay Payload (wraps the data channel JSON)

struct OverlayPayload: Codable {
    let overlays: [OverlayCommand]
    let instruction: String?
}

// MARK: - Animation Command

struct AnimationCommand: Codable, Sendable {
    let animation: String
    let instruction: String
    let x: Double?
    let y: Double?
}

// MARK: - Color from hex string

extension Color {
    init(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }

        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)

        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}
