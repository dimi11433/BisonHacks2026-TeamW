import SwiftUI
import Combine

@Observable
final class AssemblyViewModel {
    
    // MARK: - Assembly State
    var currentStepIndex: Int = 0
    var steps: [AssemblyStep] = AssemblyStep.malmBedSteps
    
    var currentStep: AssemblyStep {
        steps[currentStepIndex]
    }
    
    var totalSteps: Int { steps.count }
    var progress: Double { Double(currentStepIndex + 1) / Double(totalSteps) }
    
    // MARK: - Voice State
    var voiceState: VoiceTriggerState = .idle
    var isListening: Bool { voiceState == .listening }
    
    // MARK: - Connection State
    var isGlassesConnected: Bool = true
    var isUsingGlasses: Bool = false
    
    // MARK: - Waveform Animation
    var waveformAmplitudes: [CGFloat] = Array(repeating: 0.1, count: 7)
    private var waveformTimer: Timer?
    
    // MARK: - Navigation
    
    func nextStep() {
        guard currentStepIndex < steps.count - 1 else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentStepIndex += 1
        }
    }
    
    func previousStep() {
        guard currentStepIndex > 0 else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentStepIndex -= 1
        }
    }
    
    // MARK: - Voice Trigger
    
    func toggleVoice() {
        switch voiceState {
        case .idle:
            voiceState = .listening
            startWaveformAnimation()
            simulateVoiceFlow()
        case .listening:
            voiceState = .idle
            stopWaveformAnimation()
        default:
            break
        }
    }
    
    private func simulateVoiceFlow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard self?.voiceState == .listening else { return }
            self?.voiceState = .processing
            self?.stopWaveformAnimation()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.voiceState = .speaking
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.voiceState = .idle
                }
            }
        }
    }
    
    // MARK: - Waveform
    
    private func startWaveformAnimation() {
        waveformTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.waveformAmplitudes = (0..<7).map { _ in
                CGFloat.random(in: 0.15...1.0)
            }
        }
    }
    
    private func stopWaveformAnimation() {
        waveformTimer?.invalidate()
        waveformTimer = nil
        withAnimation(.easeOut(duration: 0.3)) {
            waveformAmplitudes = Array(repeating: 0.1, count: 7)
        }
    }
}
