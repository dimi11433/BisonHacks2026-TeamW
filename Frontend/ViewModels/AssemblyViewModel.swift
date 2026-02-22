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
    var voiceState: VoiceTriggerState = .listening
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

    // MARK: - LiveKit
    #if canImport(UIKit)
    let liveKit = LiveKitManager()
    #endif

    var boundingBoxes: [BoundingBox] {
        #if canImport(UIKit)
        liveKit.boundingBoxes
        #else
        []
        #endif
    }

    var isLiveKitConnected: Bool {
        #if canImport(UIKit)
        liveKit.isConnected
        #else
        false
        #endif
    }

    func connectLiveKit() {
        #if canImport(UIKit)
        liveKit.onAgentStoppedSpeaking = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard self.voiceState == .responding else { return }
                self.voiceState = .listening
                self.startWaveformAnimation()
                await self.liveKit.setMicEnabled(true)
            }
        }
        liveKit.onGlassesDisconnected = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.cameraSource = .phone
            }
        }
        let useGlasses = cameraSource == .glasses
        Task {
            await liveKit.connect(useGlassesCamera: useGlasses)
            await MainActor.run {
                startWaveformAnimation()
            }
        }
        #endif
    }

    func disconnectLiveKit() {
        #if canImport(UIKit)
        Task {
            await liveKit.disconnect()
        }
        #endif
    }
    
    // MARK: - Lifecycle
    
    func detectGlasses() async {
        isDetectingGlasses = true
        
        let wearables = Wearables.shared
        
        // Give the SDK a moment to discover devices
        try? await Task.sleep(for: .milliseconds(500))
        
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
        disconnectLiveKit()
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
        #if canImport(UIKit)
        switch voiceState {
        case .listening:
            voiceState = .responding
            stopWaveformAnimation()
            Task { await liveKit.setMicEnabled(false) }
        case .responding:
            voiceState = .listening
            startWaveformAnimation()
            Task { await liveKit.setMicEnabled(true) }
        }
        #endif
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
