import Foundation
import SwiftUI

// Represents one overlay drawn by the AI agent on the camera feed.
// All coordinate fields are normalized 0.0–1.0 (0,0 = top-left).
struct OverlayItem: Identifiable, Decodable {
    let id: UUID

    let type: String        // "icon" | "circle" | "region" | "arrow" | "label"

    // shared / positional
    let x: Double?
    let y: Double?
    let label: String?
    let color: String?      // hex string e.g. "#00FFFF"
    let pulse: Bool?

    // icon
    let asset: String?      // SF Symbol name
    let scale: Double?

    // circle
    let radius: Double?

    // region
    let x_min: Double?
    let y_min: Double?
    let x_max: Double?
    let y_max: Double?

    // arrow
    let from_x: Double?
    let from_y: Double?
    let to_x: Double?
    let to_y: Double?

    enum CodingKeys: String, CodingKey {
        case type, x, y, label, color, pulse
        case asset, scale
        case radius
        case x_min, y_min, x_max, y_max
        case from_x, from_y, to_x, to_y
    }

    init(from decoder: Decoder) throws {
        id = UUID()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type   = try c.decode(String.self, forKey: .type)
        x      = try c.decodeIfPresent(Double.self, forKey: .x)
        y      = try c.decodeIfPresent(Double.self, forKey: .y)
        label  = try c.decodeIfPresent(String.self, forKey: .label)
        color  = try c.decodeIfPresent(String.self, forKey: .color)
        pulse  = try c.decodeIfPresent(Bool.self,   forKey: .pulse)
        asset  = try c.decodeIfPresent(String.self, forKey: .asset)
        scale  = try c.decodeIfPresent(Double.self, forKey: .scale)
        radius = try c.decodeIfPresent(Double.self, forKey: .radius)
        x_min  = try c.decodeIfPresent(Double.self, forKey: .x_min)
        y_min  = try c.decodeIfPresent(Double.self, forKey: .y_min)
        x_max  = try c.decodeIfPresent(Double.self, forKey: .x_max)
        y_max  = try c.decodeIfPresent(Double.self, forKey: .y_max)
        from_x = try c.decodeIfPresent(Double.self, forKey: .from_x)
        from_y = try c.decodeIfPresent(Double.self, forKey: .from_y)
        to_x   = try c.decodeIfPresent(Double.self, forKey: .to_x)
        to_y   = try c.decodeIfPresent(Double.self, forKey: .to_y)
    }
}

extension Color {
    init(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt(hex, radix: 16) ?? 0x00FFFF
        self.init(hex: value)
    }
}
