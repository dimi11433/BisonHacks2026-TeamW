import SwiftUI

struct GlassmorphismHUD: View {
    let step: AssemblyStep
    let totalSteps: Int
    let progress: Double
    let onNext: () -> Void
    let onPrevious: () -> Void
    
    @State private var appear = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // Step counter + progress
            HStack {
                Label("STEP \(step.id) OF \(totalSteps)", systemImage: step.icon)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Color(hex: 0x00FFFF))
                
                Spacer()
                
                Text("\(step.estimatedMinutes) min")
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.1))
                        .frame(height: 3)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0x00FFFF), Color(hex: 0x00FFFF).opacity(0.6)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress, height: 3)
                        .animation(.spring(response: 0.5), value: progress)
                }
            }
            .frame(height: 3)
            
            // Instruction title
            Text(step.title)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
            
            // Instruction detail
            Text(step.instruction)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            
            // Parts chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(step.partsNeeded, id: \.self) { part in
                        Text(part)
                            .font(.system(.caption2, design: .rounded, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(hex: 0x00FFFF).opacity(0.15), in: Capsule())
                            .overlay(Capsule().stroke(Color(hex: 0x00FFFF).opacity(0.3), lineWidth: 0.5))
                    }
                }
            }
            
            // Navigation buttons
            HStack(spacing: 12) {
                Button(action: onPrevious) {
                    Image(systemName: "chevron.left")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 44, height: 36)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }
                .disabled(step.id == 1)
                .opacity(step.id == 1 ? 0.3 : 1)
                
                Button(action: onNext) {
                    HStack(spacing: 6) {
                        Text(step.id == totalSteps ? "Finish" : "Next Step")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        if step.id < totalSteps {
                            Image(systemName: "chevron.right")
                                .font(.system(.caption, design: .rounded, weight: .bold))
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(.caption, design: .rounded, weight: .bold))
                        }
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Color(hex: 0x00FFFF), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.15), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
        .padding(.horizontal, 16)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : -20)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2)) {
                appear = true
            }
        }
    }
}
