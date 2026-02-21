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
    private var detectionTask: Task<Void, Never>?
    
    // MARK: - Waveform Animation
    var waveformAmplitudes: [CGFloat] = Array(repeating: 0.1, count: 7)
    private var waveformTimer: Timer?
    
    // MARK: - Lifecycle
    
    func detectGlasses() {
        detectionTask?.cancel()
        detectionTask = Task { @MainActor in
            await detectGlassesAsync()
        }
    }
    
    private func detectGlassesAsync() async {
        isDetectingGlasses = true
        let wearables = Wearables.shared
        
        print("[MWDAT] detectGlasses: registrationState = \(wearables.registrationState)")
        print("[MWDAT] detectGlasses: devices (sync) = \(wearables.devices)")
        
        if let device = findConnectedDevice(wearables: wearables) {
            print("[MWDAT] detectGlasses: found connected device immediately: \(device.name), linkState=\(device.linkState), type=\(device.deviceType())")
            applyDevice(device)
            isDetectingGlasses = false
            startDevicesListener(wearables: wearables)
            return
        }
        
        print("[MWDAT] detectGlasses: no device yet, waiting on devicesStream (10s timeout)...")
        let found = await waitForDevice(wearables: wearables, timeout: 10.0)
        
        if !found {
            print("[MWDAT] detectGlasses: timed out, no connected glasses found")
            isGlassesConnected = false
            cameraSource = .phone
            connectedDeviceName = ""
        }
        
        isDetectingGlasses = false
        startDevicesListener(wearables: wearables)
    }
    
    private func waitForDevice(wearables: any WearablesInterface, timeout: TimeInterval) async -> Bool {
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await deviceIds in wearables.devicesStream() {
                    if Task.isCancelled { return false }
                    print("[MWDAT] devicesStream emitted: \(deviceIds)")
                    for id in deviceIds {
                        guard let device = wearables.deviceForIdentifier(id) else { continue }
                        print("[MWDAT] device: \(device.name), linkState=\(device.linkState), type=\(device.deviceType())")
                        
                        if device.linkState == .connected {
                            await MainActor.run {
                                self.applyDevice(device)
                            }
                            return true
                        }
                        
                        // Device exists but isn't connected yet -- wait for link state
                        if device.linkState == .connecting {
                            print("[MWDAT] device is connecting, waiting for link state change...")
                            let connected = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                                var resumed = false
                                let token = device.addLinkStateListener { state in
                                    print("[MWDAT] linkState changed to: \(state)")
                                    guard !resumed else { return }
                                    if state == .connected {
                                        resumed = true
                                        continuation.resume(returning: true)
                                    }
                                }
                                
                                Task {
                                    try? await Task.sleep(for: .seconds(3))
                                    guard !resumed else { return }
                                    resumed = true
                                    await token.cancel()
                                    continuation.resume(returning: false)
                                }
                            }
                            
                            if connected {
                                await MainActor.run {
                                    self.applyDevice(device)
                                }
                                return true
                            }
                        }
                    }
                }
                return false
            }
            
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return false
            }
            
            if let result = await group.next() {
                group.cancelAll()
                return result
            }
            return false
        }
    }
    
    private func findConnectedDevice(wearables: any WearablesInterface) -> Device? {
        for id in wearables.devices {
            if let device = wearables.deviceForIdentifier(id) {
                print("[MWDAT] findConnectedDevice: \(device.name), linkState=\(device.linkState)")
                if device.linkState == .connected {
                    return device
                }
            }
        }
        return nil
    }
    
    @MainActor
    private func applyDevice(_ device: Device) {
        print("[MWDAT] applyDevice: \(device.name), requesting camera permission...")
        isGlassesConnected = true
        cameraSource = .glasses
        connectedDeviceName = device.name
        
        Task {
            do throws(PermissionError) {
                let status = try await Wearables.shared.requestPermission(.camera)
                print("[MWDAT] Camera permission result: \(status)")
                if status == .denied {
                    self.cameraSource = .phone
                }
            } catch {
                print("[MWDAT] Camera permission request failed: \(error)")
            }
        }
        
        linkStateToken = device.addLinkStateListener { [weak self] state in
            Task { @MainActor in
                self?.isGlassesConnected = (state == .connected)
                self?.cameraSource = (state == .connected) ? .glasses : .phone
            }
        }
    }
    
    private func startDevicesListener(wearables: any WearablesInterface) {
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
    }
    
    func cleanup() {
        detectionTask?.cancel()
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
