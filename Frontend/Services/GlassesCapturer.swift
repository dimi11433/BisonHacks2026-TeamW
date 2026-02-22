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

        do {
            let status = try await wearables.requestPermission(.camera)
            guard status == .granted else {
                print("[Glasses] Camera permission denied")
                return false
            }
        } catch {
            print("[Glasses] Permission error: \(error)")
            return false
        }

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
            if state == .stopped {
                Task { @MainActor in
                    self?.onDisconnected?()
                }
            }
        }

        await session.start()

        let currentState = session.state
        guard currentState == .streaming || currentState == .starting else {
            print("[Glasses] Stream session failed to start, state: \(currentState)")
            await cleanUp()
            return false
        }

        print("[Glasses] Streaming started")
        return true
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
        print("[Glasses] Streaming stopped")
    }
}

#endif
