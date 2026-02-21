import SwiftUI

struct BoundingBoxOverlay: View {
    let boxes: [BoundingBox]

    private let cyan = Color(hex: 0x00FFFF)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ForEach(boxes) { box in
                let rect = CGRect(
                    x: box.x_min * w,
                    y: box.y_min * h,
                    width: box.width * w,
                    height: box.height * h
                )

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(cyan, lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .shadow(color: cyan.opacity(0.5), radius: 6)

                    Text(box.label)
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(cyan, in: RoundedRectangle(cornerRadius: 3))
                        .offset(y: -20)
                }
                .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
    }
}
