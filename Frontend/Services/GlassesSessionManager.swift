#if canImport(UIKit)
import Foundation
import AVFoundation
import UIKit
import CoreMedia
import MWDATCore
import MWDATCamera

@Observable
final class GlassesSessionManager {

    enum RegistrationState: String {
        case unknown = "Checking..."
        case unavailable = "Unavailable"
        case available = "Not Connected"
        case registering = "Connecting..."
        case registered = "Connected"
    }

    enum CameraPermissionState: String {
        case unknown = "Checking..."
        case denied = "Denied"
        case granted = "Granted"
    }

    enum StreamState: String {
        case stopped = "Stopped"
        case waitingForDevice = "Waiting for Device"
        case starting = "Starting..."
        case streaming = "Streaming"
        case paused = "Paused"
    }

    // MARK: - Public State

    var registrationState: RegistrationState = .unknown
    var cameraPermission: CameraPermissionState = .unknown
    var streamState: StreamState = .stopped
    var isStreaming: Bool { streamState == .streaming }

    // MARK: - Private

    private var streamSession: StreamSession?
    private var stateToken: (any AnyListenerToken)?
    private var frameToken: (any AnyListenerToken)?
    private var photoToken: (any AnyListenerToken)?
    private var registrationTask: Task<Void, Never>?
    private var devicesTask: Task<Void, Never>?

    var onFrameCaptured: ((CMSampleBuffer) -> Void)?

    // MARK: - Registration

    func checkRegistration() {
        let wearables = Wearables.shared

        // Read current state synchronously so callers see it immediately
        applyRegistrationState(wearables.registrationState)

        registrationTask = Task {
            for await state in wearables.registrationStateStream() {
                await MainActor.run {
                    self.applyRegistrationState(state)
                }
            }
        }
    }

    private func applyRegistrationState(_ state: MWDATCore.RegistrationState) {
        switch state {
        case .registered:
            registrationState = .registered
            Task { await checkCameraPermission() }
        case .available:
            registrationState = .available
        case .registering:
            registrationState = .registering
        case .unavailable:
            registrationState = .unavailable
        @unknown default:
            registrationState = .unknown
        }
        print("[Glasses] Registration state: \(registrationState.rawValue)")
    }

    func startRegistration() {
        registrationState = .registering
        Task {
            do {
                try await Wearables.shared.startRegistration()
            } catch {
                print("[Glasses] Registration failed: \(error)")
            }
        }
    }

    func handleUrl(_ url: URL) async {
        do {
            _ = try await Wearables.shared.handleUrl(url)
        } catch {
            print("[Glasses] URL handling failed: \(error)")
        }
    }

    // MARK: - Camera Permission

    func checkCameraPermission() async {
        guard registrationState == .registered else { return }
        do {
            let status = try await Wearables.shared.checkPermissionStatus(.camera)
            switch status {
            case .granted:
                cameraPermission = .granted
            case .denied:
                cameraPermission = .denied
            }
        } catch {
            print("[Glasses] Permission check skipped: \(error)")
        }
    }

    func requestCameraPermission() async {
        do {
            let status = try await Wearables.shared.requestPermission(.camera)
            switch status {
            case .granted:
                cameraPermission = .granted
            case .denied:
                cameraPermission = .denied
            }
        } catch {
            print("[Glasses] Permission request failed: \(error)")
        }
    }

    // MARK: - Audio (HFP)

    func configureHFPAudio() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            print("[Glasses] HFP audio session configured")
        } catch {
            print("[Glasses] Audio session error: \(error)")
        }
    }

    // MARK: - Streaming

    func startStreaming() async {
        let wearables = Wearables.shared
        let deviceSelector = AutoDeviceSelector(wearables: wearables)

        let config = StreamSessionConfig(
            videoCodec: .raw,
            resolution: .low,
            frameRate: 15
        )

        let session = StreamSession(streamSessionConfig: config, deviceSelector: deviceSelector)
        streamSession = session

        stateToken = session.statePublisher.listen { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .stopped, .stopping:
                    self.streamState = .stopped
                case .waitingForDevice:
                    self.streamState = .waitingForDevice
                case .starting:
                    self.streamState = .starting
                case .streaming:
                    self.streamState = .streaming
                case .paused:
                    self.streamState = .paused
                @unknown default:
                    self.streamState = .stopped
                }
            }
        }

        frameToken = session.videoFramePublisher.listen { [weak self] frame in
            guard let self else { return }
            let sampleBuffer = frame.sampleBuffer
            Task { @MainActor in
                self.onFrameCaptured?(sampleBuffer)
            }
        }

        configureHFPAudio()
        try? await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)

        await session.start()
        print("[Glasses] Stream session started")
    }

    func stopStreaming() async {
        guard streamSession != nil else { return }
        if let session = streamSession {
            await session.stop()
        }
        await stateToken?.cancel()
        await frameToken?.cancel()
        await photoToken?.cancel()
        streamSession = nil
        streamState = .stopped
        print("[Glasses] Stream session stopped")
    }

    // MARK: - Cleanup

    func cleanup() {
        registrationTask?.cancel()
        devicesTask?.cancel()
        Task {
            await stopStreaming()
        }
    }
}

#endif
