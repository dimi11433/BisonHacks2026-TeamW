import SwiftUI
import Combine
import MWDATCore

enum CameraSource: String {
    case phone = "iPhone Camera"
    case glasses = "Meta Ray-Ban"
    
    var icon: String {
        switch self {
        case .phone:   return "iphone"
        case .glasses: return "eyeglasses"
        }
    }
}

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
    
    // MARK: - Connection & Camera Source
    var isGlassesConnected: Bool = false
    var cameraSource: CameraSource = .phone
    var connectedDeviceName: String = ""
    var isDetectingGlasses: Bool = false
    
    private var linkStateToken: (any AnyListenerToken)?
    private var devicesToken: (any AnyListenerToken)?
    
    // MARK: - Waveform Animation
    var waveformAmplitudes: [CGFloat] = Array(repeating: 0.1, count: 7)
    private var waveformTimer: Timer?
    
    // MARK: - Lifecycle
    
    func detectGlasses() {
        isDetectingGlasses = true
        
        let wearables = Wearables.shared
        let deviceIds = wearables.devices
        
        if let firstId = deviceIds.first,
           let device = wearables.deviceForIdentifier(firstId) {
            let linked = device.linkState == .connected
            isGlassesConnected = linked
            cameraSource = linked ? .glasses : .phone
            connectedDeviceName = device.name
            
            linkStateToken = device.addLinkStateListener { [weak self] state in
                Task { @MainActor in
                    self?.isGlassesConnected = (state == .connected)
                    self?.cameraSource = (state == .connected) ? .glasses : .phone
                }
            }
        } else {
            isGlassesConnected = false
            cameraSource = .phone
        }
        
        devicesToken = wearables.addDevicesListener { [weak self] ids in
            Task { @MainActor in
                guard let self else { return }
                if let firstId = ids.first,
                   let device = wearables.deviceForIdentifier(firstId) {
                    self.isGlassesConnected = (device.linkState == .connected)
                    self.cameraSource = (device.linkState == .connected) ? .glasses : .phone
                    self.connectedDeviceName = device.name
                } else {
                    self.isGlassesConnected = false
                    self.cameraSource = .phone
                    self.connectedDeviceName = ""
                }
            }
        }
        
        isDetectingGlasses = false
    }
    
    func cleanup() {
        Task {
            await linkStateToken?.cancel()
            await devicesToken?.cancel()
        }
    }
    
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
