#if canImport(UIKit)
import SwiftUI

struct OverlayRenderer: View {
    let overlays: [OverlayCommand]
    let instruction: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geo in
                ForEach(overlays) { cmd in
                    switch cmd.type {
                    case .icon:
                        IconOverlayView(command: cmd, size: geo.size)
                    case .arrow:
                        ArrowOverlayView(command: cmd, size: geo.size)
                    case .circle:
                        CircleOverlayView(command: cmd, size: geo.size)
                    case .region:
                        RegionOverlayView(command: cmd, size: geo.size)
                    case .label:
                        LabelOverlayView(command: cmd, size: geo.size)
                    }
                }
            }

            if let instruction, !instruction.isEmpty {
                InstructionBanner(text: instruction)
                    .padding(.bottom, 120)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Icon Overlay

private struct IconOverlayView: View {
    let command: OverlayCommand
    let size: CGSize
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 1.0

    var body: some View {
        let px = (command.x ?? 0.5) * size.width
        let py = (command.y ?? 0.5) * size.height

        VStack(spacing: 4) {
            Image(systemName: command.asset ?? "questionmark.circle")
                .font(.system(size: 28 * command.resolvedScale))
                .foregroundStyle(command.resolvedColor)
                .shadow(color: command.resolvedColor.opacity(0.6), radius: 8)
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)

            if let label = command.label {
                Text(label)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.6), in: Capsule())
            }
        }
        .position(x: px, y: py)
        .onAppear {
            guard command.shouldPulse else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulseScale = 1.15
                pulseOpacity = 0.7
            }
        }
    }
}

// MARK: - Arrow Overlay

private struct ArrowOverlayView: View {
    let command: OverlayCommand
    let size: CGSize

    var body: some View {
        let fx = (command.from_x ?? 0) * size.width
        let fy = (command.from_y ?? 0) * size.height
        let tx = (command.to_x ?? 0) * size.width
        let ty = (command.to_y ?? 0) * size.height
        let color = command.resolvedColor

        Canvas { context, _ in
            let from = CGPoint(x: fx, y: fy)
            let to = CGPoint(x: tx, y: ty)

            var linePath = Path()
            linePath.move(to: from)
            linePath.addLine(to: to)
            context.stroke(linePath, with: .color(color), lineWidth: 3)

            let angle = atan2(ty - fy, tx - fx)
            let headLength: CGFloat = 14
            let headAngle: CGFloat = .pi / 6

            var headPath = Path()
            headPath.move(to: to)
            headPath.addLine(to: CGPoint(
                x: tx - headLength * cos(angle - headAngle),
                y: ty - headLength * sin(angle - headAngle)
            ))
            headPath.addLine(to: CGPoint(
                x: tx - headLength * cos(angle + headAngle),
                y: ty - headLength * sin(angle + headAngle)
            ))
            headPath.closeSubpath()
            context.fill(headPath, with: .color(color))
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Circle Overlay

private struct CircleOverlayView: View {
    let command: OverlayCommand
    let size: CGSize
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        let px = (command.x ?? 0.5) * size.width
        let py = (command.y ?? 0.5) * size.height
        let diameter = command.resolvedRadius * 2 * min(size.width, size.height)
        let color = command.resolvedColor

        ZStack {
            Circle()
                .stroke(color, lineWidth: 2.5)
                .frame(width: diameter, height: diameter)

            Circle()
                .fill(color.opacity(0.15))
                .frame(width: diameter, height: diameter)

            if let label = command.label {
                Text(label)
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(y: diameter / 2 + 14)
            }
        }
        .scaleEffect(pulseScale)
        .position(x: px, y: py)
        .onAppear {
            guard command.shouldPulse else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulseScale = 1.2
            }
        }
    }
}

// MARK: - Region Overlay

private struct RegionOverlayView: View {
    let command: OverlayCommand
    let size: CGSize

    var body: some View {
        let x = (command.x_min ?? 0) * size.width
        let y = (command.y_min ?? 0) * size.height
        let w = ((command.x_max ?? 0) - (command.x_min ?? 0)) * size.width
        let h = ((command.y_max ?? 0) - (command.y_min ?? 0)) * size.height
        let color = command.resolvedColor
        let isDashed = command.style == "dashed"

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    color,
                    style: StrokeStyle(
                        lineWidth: 2.5,
                        dash: isDashed ? [8, 6] : []
                    )
                )
                .frame(width: w, height: h)

            if let label = command.label {
                Text(label)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                    .offset(y: -22)
            }
        }
        .position(x: x + w / 2, y: y + h / 2)
    }
}

// MARK: - Label Overlay

private struct LabelOverlayView: View {
    let command: OverlayCommand
    let size: CGSize

    var body: some View {
        let px = (command.x ?? 0.5) * size.width
        let py = (command.y ?? 0.5) * size.height
        let color = command.resolvedColor

        Text(command.label ?? "")
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
            .position(x: px, y: py)
    }
}

// MARK: - Instruction Banner

private struct InstructionBanner: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
    }
}

#endif
