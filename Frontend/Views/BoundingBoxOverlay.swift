#if canImport(UIKit)
import SwiftUI

/// 2D overlay that draws bounding boxes on top of a flat video feed (e.g. glasses camera).
/// Normalized coordinates (0…1) are mapped to the parent geometry's size.
struct BoundingBoxOverlay: View {
    let boxes: [BoundingBox]

    private let cyan = Color(red: 0, green: 1, blue: 1)

    var body: some View {
        GeometryReader { geo in
            ForEach(boxes) { box in
                let x = box.x_min * geo.size.width
                let y = box.y_min * geo.size.height
                let w = box.width * geo.size.width
                let h = box.height * geo.size.height

                Rectangle()
                    .stroke(cyan, lineWidth: 2)
                    .frame(width: w, height: h)
                    .overlay(alignment: .topLeading) {
                        Text(box.label)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(cyan)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                            .offset(y: -20)
                    }
                    .position(x: x + w / 2, y: y + h / 2)
            }
        }
        .allowsHitTesting(false)
    }
}
#endif
