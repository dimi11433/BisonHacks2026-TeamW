#if canImport(UIKit)
import Foundation
import CoreMedia
import MWDATCore
import MWDATCamera
import LiveKit

@MainActor
final class GlassesCapturer: Sendable {

    private var streamSession: StreamSession?
    private var frameListenerToken: (any AnyListenerToken)?
    private var stateListenerToken: (any AnyListenerToken)?

    private let bufferCapturer: BufferCapturer
    let videoTrack: LocalVideoTrack

    var onDisconnected: (@Sendable () -> Void)?
    var onStreaming: (@Sendable () -> Void)?

    init() {
        let track = LocalVideoTrack.createBufferTrack(
            name: "glasses-camera",
            source: .camera,
            options: BufferCaptureOptions()
        )
        self.videoTrack = track
        self.bufferCapturer = track.capturer as! BufferCapturer
    }

    func start() async -> Bool {
        let wearables = Wearables.shared

        let config = StreamSessionConfig(
            videoCodec: .raw,
            resolution: .high,
            frameRate: 30
        )
        let selector = AutoDeviceSelector(wearables: wearables)
        let session = StreamSession(streamSessionConfig: config, deviceSelector: selector)
        self.streamSession = session

        frameListenerToken = session.videoFramePublisher.listen { [weak self] videoFrame in
            self?.bufferCapturer.capture(videoFrame.sampleBuffer)
        }

        stateListenerToken = session.statePublisher.listen { [weak self] state in
            print("[Glasses] State changed: \(state)")
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .streaming:
                    print("[Glasses] Now streaming from glasses")
                    self.onStreaming?()
                case .stopped:
                    self.onDisconnected?()
                case .waitingForDevice:
                    print("[Glasses] Waiting for glasses to connect...")
                default:
                    break
                }
            }
        }

        await session.start()
        print("[Glasses] Session started, state: \(session.state)")

        // waitingForDevice is normal — the AutoDeviceSelector will find glasses
        // when they connect. Wait briefly for streaming to begin, then fall back.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let state = session.state
            if state == .streaming {
                print("[Glasses] Streaming confirmed")
                await requestCameraPermission(wearables: wearables)
                return true
            }
            if state == .stopped {
                print("[Glasses] Session stopped unexpectedly")
                await cleanUp()
                return false
            }
            try? await Task.sleep(for: .milliseconds(500))
        }

        // Still in waitingForDevice or starting after timeout —
        // keep session alive in background, it'll connect when glasses pair
        let state = session.state
        if state == .waitingForDevice || state == .starting {
            print("[Glasses] Glasses not found within timeout, keeping session alive in background")
            return false
        }

        print("[Glasses] Unexpected state after timeout: \(state)")
        await cleanUp()
        return false
    }

    private func requestCameraPermission(wearables: any WearablesInterface) async {
        do {
            let status = try await wearables.requestPermission(.camera)
            print("[Glasses] Camera permission: \(status)")
        } catch {
            print("[Glasses] Permission error (non-fatal): \(error)")
        }
    }

    func stop() async {
        await cleanUp()
    }

    private func cleanUp() async {
        if let token = frameListenerToken {
            await token.cancel()
            frameListenerToken = nil
        }
        if let token = stateListenerToken {
            await token.cancel()
            stateListenerToken = nil
        }
        if let session = streamSession {
            await session.stop()
            streamSession = nil
        }
        print("[Glasses] Stopped and cleaned up")
    }
}

#endif
