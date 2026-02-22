import Foundation

struct BoundingBox: Identifiable, Codable, Sendable {
    let type: String?
    let label: String
    let y_min: Double
    let x_min: Double
    let y_max: Double
    let x_max: Double

    var id: String { "\(label)-\(x_min)-\(y_min)" }
    var width: Double { x_max - x_min }
    var height: Double { y_max - y_min }
}