import SwiftUI
import Combine

// Renders all AI-drawn overlays on top of the camera feed.
// Coordinates from the backend are normalized 0–1; we convert to screen points
// using a GeometryReader so everything scales to any device size.
struct AROverlayView: View {
    let overlays: [OverlayItem]
    let animation: String?          // "cpr_compressions" or nil
    let animationInstruction: String

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Draw every overlay
                ForEach(overlays) { item in
                    switch item.type {
                    case "icon":   IconOverlay(item: item, size: geo.size)
                    case "circle": CircleOverlay(item: item, size: geo.size)
                    case "region": RegionOverlay(item: item, size: geo.size)
                    case "arrow":  ArrowOverlay(item: item, size: geo.size)
                    case "label":  LabelOverlay(item: item, size: geo.size)
                    default:       EmptyView()
                    }
                }

                // CPR compressions animation (bottom of screen)
                if animation == "cpr_compressions" {
                    CPRCompressionOverlay(instruction: animationInstruction)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Icon

private struct IconOverlay: View {
    let item: OverlayItem
    let size: CGSize

    @State private var pulsing = false

    var body: some View {
        let px = CGFloat(item.x ?? 0.5) * size.width
        let py = CGFloat(item.y ?? 0.5) * size.height
        let iconSize = CGFloat(item.scale ?? 2.0) * 18
        let color = Color(hexString: item.color ?? "#00FFFF")
        let shouldPulse = item.pulse ?? true

        VStack(spacing: 4) {
            Image(systemName: item.asset ?? "questionmark.circle.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.8), radius: 8)
                .scaleEffect(shouldPulse && pulsing ? 1.25 : 1.0)
                .animation(
                    shouldPulse
                        ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                        : .default,
                    value: pulsing
                )

            if let label = item.label, !label.isEmpty {
                Text(label)
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.6), in: Capsule())
            }
        }
        .position(x: px, y: py)
        .onAppear { if shouldPulse { pulsing = true } }
    }
}

// MARK: - Circle

private struct CircleOverlay: View {
    let item: OverlayItem
    let size: CGSize

    @State private var pulsing = false

    var body: some View {
        let px = CGFloat(item.x ?? 0.5) * size.width
        let py = CGFloat(item.y ?? 0.5) * size.height
        let r  = CGFloat(item.radius ?? 0.05) * size.width * 2
        let color = Color(hexString: item.color ?? "#FF3B30")
        let shouldPulse = item.pulse ?? true

        ZStack {
            Circle()
                .stroke(color, lineWidth: 2.5)
                .frame(width: r, height: r)
                .shadow(color: color.opacity(0.7), radius: 6)
                .scaleEffect(shouldPulse && pulsing ? 1.2 : 1.0)
                .opacity(shouldPulse && pulsing ? 0.6 : 1.0)
                .animation(
                    shouldPulse
                        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                        : .default,
                    value: pulsing
                )

            if let label = item.label, !label.isEmpty {
                Text(label)
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.6), in: Capsule())
                    .offset(y: r / 2 + 10)
            }
        }
        .position(x: px, y: py)
        .onAppear { if shouldPulse { pulsing = true } }
    }
}

// MARK: - Region

private struct RegionOverlay: View {
    let item: OverlayItem
    let size: CGSize

    var body: some View {
        let xMin = CGFloat(item.x_min ?? 0) * size.width
        let yMin = CGFloat(item.y_min ?? 0) * size.height
        let xMax = CGFloat(item.x_max ?? 1) * size.width
        let yMax = CGFloat(item.y_max ?? 1) * size.height
        let w = xMax - xMin
        let h = yMax - yMin
        let color = Color(hexString: item.color ?? "#00FFFF")

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .stroke(color, lineWidth: 2)
                .frame(width: w, height: h)
                .shadow(color: color.opacity(0.5), radius: 4)

            if let label = item.label, !label.isEmpty {
                Text(label)
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                    .offset(x: 4, y: -20)
            }
        }
        .position(x: xMin + w / 2, y: yMin + h / 2)
    }
}

// MARK: - Arrow

private struct ArrowOverlay: View {
    let item: OverlayItem
    let size: CGSize

    var body: some View {
        let fx = CGFloat(item.from_x ?? 0) * size.width
        let fy = CGFloat(item.from_y ?? 0) * size.height
        let tx = CGFloat(item.to_x ?? 1) * size.width
        let ty = CGFloat(item.to_y ?? 1) * size.height
        let color = Color(hexString: item.color ?? "#FFFFFF")

        Canvas { ctx, _ in
            let start = CGPoint(x: fx, y: fy)
            let end   = CGPoint(x: tx, y: ty)
            let style = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)

            // Shaft
            var shaft = Path()
            shaft.move(to: start)
            shaft.addLine(to: end)
            ctx.stroke(shaft, with: .color(color), style: style)

            // Arrowhead
            let angle: CGFloat = atan2(ty - fy, tx - fx)
            let len: CGFloat   = 18
            let spread: CGFloat = .pi / 6
            let p1 = CGPoint(x: end.x - len * cos(angle - spread),
                             y: end.y - len * sin(angle - spread))
            let p2 = CGPoint(x: end.x - len * cos(angle + spread),
                             y: end.y - len * sin(angle + spread))
            var head = Path()
            head.move(to: end); head.addLine(to: p1)
            head.move(to: end); head.addLine(to: p2)
            ctx.stroke(head, with: .color(color), style: style)
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Label

private struct LabelOverlay: View {
    let item: OverlayItem
    let size: CGSize

    var body: some View {
        let px = CGFloat(item.x ?? 0.5) * size.width
        let py = CGFloat(item.y ?? 0.5) * size.height
        let color = Color(hexString: item.color ?? "#FFFFFF")

        Text(item.label ?? "")
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.5), lineWidth: 1))
            .shadow(color: color.opacity(0.4), radius: 6)
            .position(x: px, y: py)
    }
}

// MARK: - CPR Compression Animation

private struct CPRCompressionOverlay: View {
    let instruction: String
    @State private var compressionCount = 0
    private let timer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 12) {
                // Instruction
                if !instruction.isEmpty {
                    Text(instruction)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 20)
                }

                // Animated hands
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    let elapsed = timeline.date.timeIntervalSinceReferenceDate
                    let phase  = elapsed.truncatingRemainder(dividingBy: 0.6) / 0.6
                    let offset = CGFloat(compressionCurve(phase: phase)) * 46

                    ZStack {
                        // Person outline
                        VStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(.white.opacity(0.18), lineWidth: 1.2)
                                .frame(width: 28, height: 14)
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(.white.opacity(0.25), lineWidth: 1.5)
                                .frame(width: 160, height: 78)
                        }
                        .offset(y: 42)

                        Circle()
                            .fill(.red.opacity(0.7))
                            .frame(width: 12, height: 12)
                            .offset(y: 38)

                        // Arrows
                        VStack(spacing: 6) {
                            ForEach(0..<3, id: \.self) { i in
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.arCyan)
                                    .opacity(arrowAlpha(phase: phase) * max(0.2, 1.0 - Double(i) * 0.3))
                            }
                        }
                        .offset(y: -74 + offset * 0.35)
                        .opacity(arrowAlpha(phase: phase))

                        // Hands
                        ZStack {
                            Image(systemName: "hand.raised")
                                .font(.system(size: 58, weight: .ultraLight))
                                .foregroundStyle(.white.opacity(0.4))
                                .rotationEffect(.degrees(180))
                                .scaleEffect(0.9)
                                .offset(x: 2, y: 7)
                            Image(systemName: "hand.raised")
                                .font(.system(size: 58, weight: .ultraLight))
                                .foregroundStyle(.white)
                                .rotationEffect(.degrees(180))
                        }
                        .offset(y: -20 + offset)
                    }
                    .frame(height: 180)
                }

                // Stats
                HStack(spacing: 18) {
                    Label("100 BPM", systemImage: "heart.fill")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.red)
                    Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 14)
                    Text("\(compressionCount) compressions")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .contentTransition(.numericText())
                        .animation(.linear(duration: 0.1), value: compressionCount)
                }
            }
            .padding(.vertical, 16)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )

            Spacer().frame(height: 100)
        }
        .onReceive(timer) { _ in compressionCount += 1 }
    }

    private func compressionCurve(phase: Double) -> Double {
        if phase < 0.35 { let t = phase / 0.35; return t * t }
        if phase < 0.50 { return 1.0 }
        if phase < 0.85 { return 1.0 - (phase - 0.50) / 0.35 }
        return 0.0
    }

    private func arrowAlpha(phase: Double) -> Double {
        if phase < 0.35 { return phase / 0.35 }
        if phase < 0.55 { return 1.0 }
        return max(0, 1.0 - (phase - 0.55) / 0.30)
    }
}
