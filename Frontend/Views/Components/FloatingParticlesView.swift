import SwiftUI

struct FloatingParticlesView: View {
    @State private var particles: [Particle] = []
    @State private var timer: Timer?

    private let cyan = Color(hex: 0x00FFFF)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                for p in particles {
                    let age = now - p.born
                    let lifetime = p.lifetime
                    guard age < lifetime else { continue }

                    let progress = age / lifetime
                    let alpha = sin(progress * .pi) * p.maxAlpha
                    let x = p.startX + sin(age * p.driftSpeed) * p.driftAmplitude
                    let y = p.startY - CGFloat(age) * p.riseSpeed

                    let rect = CGRect(
                        x: x * size.width - p.radius,
                        y: y * size.height - p.radius,
                        width: p.radius * 2,
                        height: p.radius * 2
                    )

                    context.opacity = alpha
                    context.fill(
                        Circle().path(in: rect),
                        with: .color(p.color)
                    )
                }
            }
        }
        .onAppear { startSpawning() }
        .onDisappear { timer?.invalidate() }
    }

    private func startSpawning() {
        for _ in 0..<15 {
            particles.append(Particle.random(bornOffset: -Double.random(in: 0...4)))
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            particles.append(Particle.random())
            particles.removeAll { Date.timeIntervalSinceReferenceDate - $0.born > $0.lifetime }
        }
    }
}

private struct Particle: Identifiable {
    let id = UUID()
    let born: TimeInterval
    let lifetime: Double
    let startX: CGFloat
    let startY: CGFloat
    let radius: CGFloat
    let maxAlpha: Double
    let riseSpeed: CGFloat
    let driftSpeed: Double
    let driftAmplitude: CGFloat
    let color: Color

    static func random(bornOffset: Double = 0) -> Particle {
        let colors: [Color] = [
            Color(hex: 0x00FFFF),
            Color(hex: 0x00DDFF),
            Color(hex: 0x44FFFF),
            .white,
        ]
        return Particle(
            born: Date.timeIntervalSinceReferenceDate + bornOffset,
            lifetime: Double.random(in: 4...8),
            startX: CGFloat.random(in: 0.05...0.95),
            startY: CGFloat.random(in: 0.7...1.1),
            radius: CGFloat.random(in: 1.0...3.0),
            maxAlpha: Double.random(in: 0.15...0.45),
            riseSpeed: CGFloat.random(in: 0.015...0.04),
            driftSpeed: Double.random(in: 0.5...1.5),
            driftAmplitude: CGFloat.random(in: 0.01...0.04),
            color: colors.randomElement()!
        )
    }
}
