#if canImport(UIKit)
import Foundation
import ARKit
import CoreVideo
import LiveKit
import UIKit

/// Bridges ARSession camera frames into a LiveKit video track so the AI agent
/// continues to receive video when ARView owns the camera instead of LiveKit.
final class ARFrameCapturer: NSObject, ARSessionDelegate {

    private let bufferCapturer: BufferCapturer
    let videoTrack: LocalVideoTrack

    override init() {
        let track = LocalVideoTrack.createBufferTrack(
            name: "ar-camera",
            source: .camera,
            options: BufferCaptureOptions()
        )
        self.videoTrack = track
        self.bufferCapturer = track.capturer as! BufferCapturer
        super.init()
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let pixelBuffer = frame.capturedImage
        let tsNanos = Int64(frame.timestamp * 1_000_000_000)

        // ARSession delivers frames in the sensor's native landscape-left
        // orientation. When the phone is held portrait, the image needs a
        // 90-degree clockwise rotation so the AI sees it right-side-up.
        let rotation: VideoRotation
        switch UIDevice.current.orientation {
        case .portrait:            rotation = ._90
        case .portraitUpsideDown:  rotation = ._270
        case .landscapeLeft:       rotation = ._180
        case .landscapeRight:      rotation = ._0
        default:                   rotation = ._90
        }

        bufferCapturer.capture(pixelBuffer, timeStampNs: tsNanos, rotation: rotation)
    }
}

#endif
