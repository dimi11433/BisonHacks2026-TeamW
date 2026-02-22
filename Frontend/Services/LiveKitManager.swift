#if canImport(UIKit)
import Foundation
import AVFoundation
import LiveKit
import Combine
import UIKit

@Observable
final class LiveKitManager: NSObject {

    // MARK: - Configuration
    static var tokenServerURL = "https://f10d-138-238-254-107.ngrok-free.app"

    // MARK: - Public State
    var isConnected = false
    var isConnecting = false
    var connectionError: String?
    var localVideoTrack: VideoTrack?
    var isAgentSpeaking = false
    var usingGlasses = false

    // MARK: - Overlay State
    var activeOverlays: [OverlayCommand] = []
    var overlayInstruction: String = ""
    var activeAnimation: AnimationCommand?

    // MARK: - Callbacks
    var onAgentStoppedSpeaking: (() -> Void)?
    var onGlassesDisconnected: (() -> Void)?

    // MARK: - Private
    private let room = Room()
    private var cancellables = Set<AnyCancellable>()
    private var glassesCapturer: GlassesCapturer?

    // MARK: - Init
    override init() {
        super.init()
        room.add(delegate: self)
    }

    // MARK: - Connect
    func connect(useGlassesCamera: Bool = false, skipCamera: Bool = false) async {
        guard !isConnected, !isConnecting else { return }
        isConnecting = true
        connectionError = nil

        do {
            print("[LiveKit] Fetching token...")
            let credentials = try await fetchToken()
            print("[LiveKit] Token received. Connecting to room...")

            try await room.connect(
                url: credentials.serverURL,
                token: credentials.token
            )
            print("[LiveKit] Room connected. Setting up camera...")

            if skipCamera {
                print("[LiveKit] Skipping built-in camera (ARView will provide frames).")
            } else if useGlassesCamera {
                let capturer = GlassesCapturer()
                capturer.onDisconnected = { [weak self] in
                    Task { @MainActor in
                        guard let self else { return }
                        print("[LiveKit] Glasses disconnected, falling back to iPhone camera")
                        self.usingGlasses = false
                        self.glassesCapturer = nil
                        _ = try? await self.room.localParticipant.setCamera(
                            enabled: true,
                            captureOptions: CameraCaptureOptions(position: .back)
                        )
                        self.onGlassesDisconnected?()
                    }
                }
                glassesCapturer = capturer
                let started = await capturer.start()
                if started {
                    try await room.localParticipant.publish(videoTrack: capturer.videoTrack)
                    localVideoTrack = capturer.videoTrack
                    usingGlasses = true
                    print("[LiveKit] Glasses camera published.")
                } else {
                    print("[LiveKit] Glasses not ready yet, using iPhone camera (will switch when glasses connect)")
                    try await room.localParticipant.setCamera(
                        enabled: true,
                        captureOptions: CameraCaptureOptions(position: .back)
                    )
                    usingGlasses = false
                }
                capturer.onStreaming = { [weak self] in
                    Task { @MainActor in
                        guard let self, !self.usingGlasses else { return }
                        print("[LiveKit] Glasses connected late, switching to glasses camera")
                        do {
                            try await self.room.localParticipant.setCamera(enabled: false)
                            try await self.room.localParticipant.publish(videoTrack: capturer.videoTrack)
                            self.localVideoTrack = capturer.videoTrack
                            self.usingGlasses = true
                            self.glassesCapturer = capturer
                        } catch {
                            print("[LiveKit] Failed to switch to glasses: \(error)")
                        }
                    }
                }
            } else {
                try await room.localParticipant.setCamera(
                    enabled: true,
                    captureOptions: CameraCaptureOptions(position: .back)
                )
                usingGlasses = false
            }

            print("[LiveKit] Camera ready. Enabling mic...")

            try await room.localParticipant.setMicrophone(enabled: true)
            print("[LiveKit] Mic enabled. Checking video tracks...")

            if localVideoTrack == nil,
               let pub = room.localParticipant.localVideoTracks.first,
               let videoTrack = pub.track as? VideoTrack {
                localVideoTrack = videoTrack
                print("[LiveKit] Local video track set.")
            }

            isConnected = true
            print("[LiveKit] Fully connected!")
        } catch {
            connectionError = error.localizedDescription
            print("[LiveKit] ERROR: \(error)")
        }

        isConnecting = false
    }

    // MARK: - Publish External Video Track (e.g. from ARSession)
    func publishExternalTrack(_ track: LocalVideoTrack) async throws {
        try await room.localParticipant.publish(videoTrack: track)
        localVideoTrack = track
        print("[LiveKit] External video track published.")
    }

    // MARK: - Switch Camera Source (live, while connected)
    func switchToGlasses() async {
        guard isConnected, !usingGlasses else { return }

        let capturer = GlassesCapturer()
        capturer.onDisconnected = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                print("[LiveKit] Glasses disconnected, falling back to iPhone camera")
                self.usingGlasses = false
                self.glassesCapturer = nil
                self.onGlassesDisconnected?()
            }
        }
        glassesCapturer = capturer

        let started = await capturer.start()
        guard started else {
            print("[LiveKit] Glasses not available, cannot switch.")
            glassesCapturer = nil
            return
        }

        do {
            for pub in room.localParticipant.localVideoTracks {
                try await room.localParticipant.unpublish(publication: pub)
            }
            try await room.localParticipant.setCamera(enabled: false)
            try await room.localParticipant.publish(videoTrack: capturer.videoTrack)
            localVideoTrack = capturer.videoTrack
            usingGlasses = true
            print("[LiveKit] Switched to glasses camera.")
        } catch {
            print("[LiveKit] Failed to switch to glasses: \(error)")
        }
    }

    func switchToPhone(arCapturer: ARFrameCapturer?) async {
        guard isConnected, usingGlasses else { return }

        if let capturer = glassesCapturer {
            await capturer.stop()
            glassesCapturer = nil
        }

        do {
            for pub in room.localParticipant.localVideoTracks {
                try await room.localParticipant.unpublish(publication: pub)
            }

            if let arCapturer {
                try await room.localParticipant.publish(videoTrack: arCapturer.videoTrack)
                localVideoTrack = arCapturer.videoTrack
            } else {
                try await room.localParticipant.setCamera(
                    enabled: true,
                    captureOptions: CameraCaptureOptions(position: .back)
                )
                if let pub = room.localParticipant.localVideoTracks.first,
                   let track = pub.track as? VideoTrack {
                    localVideoTrack = track
                }
            }
            usingGlasses = false
            print("[LiveKit] Switched to iPhone camera.")
        } catch {
            print("[LiveKit] Failed to switch to phone: \(error)")
        }
    }

    // MARK: - Disconnect
    func disconnect() async {
        if let capturer = glassesCapturer {
            await capturer.stop()
            glassesCapturer = nil
        }
        await room.disconnect()
        isConnected = false
        usingGlasses = false
        localVideoTrack = nil
        activeOverlays = []
        activeAnimation = nil
        overlayInstruction = ""
    }

    // MARK: - Mic Control
    func setMicEnabled(_ enabled: Bool) async {
        do {
            try await room.localParticipant.setMicrophone(enabled: enabled)
        } catch {
            print("[LiveKit] Mic error: \(error)")
        }
    }

    // MARK: - Overlay Control
    func clearAllOverlays() {
        activeOverlays = []
        activeAnimation = nil
        overlayInstruction = ""
    }

    // MARK: - Token Fetch
    private struct TokenResponse: Codable {
        let server_url: String
        let participant_token: String
    }

    private struct Credentials {
        let serverURL: String
        let token: String
    }

    private static let localSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private func fetchToken() async throws -> Credentials {
        guard let url = URL(string: "\(Self.tokenServerURL)/getToken") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["participant_name": "iOS User"]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await Self.localSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        return Credentials(
            serverURL: tokenResponse.server_url,
            token: tokenResponse.participant_token
        )
    }
}

// MARK: - RoomDelegate
extension LiveKitManager: RoomDelegate {

    nonisolated func room(_ room: Room, participant: RemoteParticipant?, didReceiveData data: Data, forTopic topic: String, encryptionType: EncryptionType) {

        if topic == "ar_overlay" {
            print("[AR] ar_overlay received — raw: \(String(data: data, encoding: .utf8) ?? "<binary>")")
            let capturedData = data
            Task { @MainActor in
                guard let payload = try? JSONDecoder().decode(OverlayPayload.self, from: capturedData) else {
                    print("[AR] Failed to decode ar_overlay payload")
                    return
                }
                self.activeOverlays.append(contentsOf: payload.overlays)
                if let instruction = payload.instruction, !instruction.isEmpty {
                    self.overlayInstruction = instruction
                }
            }
        }

        if topic == "ar_animation" {
            print("[AR] ar_animation received — raw: \(String(data: data, encoding: .utf8) ?? "<binary>")")
            let capturedData = data
            Task { @MainActor in
                guard let anim = try? JSONDecoder().decode(AnimationCommand.self, from: capturedData) else {
                    print("[AR] Failed to decode ar_animation payload")
                    return
                }
                self.activeAnimation = anim
            }
        }

        if topic == "ar_clear" {
            print("[AR] ar_clear received")
            Task { @MainActor in
                self.clearAllOverlays()
            }
        }
    }

    nonisolated func room(_ room: Room, participant: LocalParticipant, didPublishTrack publication: LocalTrackPublication) {
        Task { @MainActor in
            if let videoTrack = publication.track as? VideoTrack {
                self.localVideoTrack = videoTrack
            }
        }
    }

    nonisolated func room(_ room: Room, participant: Participant, didUpdateIsSpeaking isSpeaking: Bool) {
        guard participant is RemoteParticipant else { return }
        Task { @MainActor in
            let wasSpeaking = self.isAgentSpeaking
            self.isAgentSpeaking = isSpeaking
            if !wasSpeaking && isSpeaking {
                self.activeOverlays = []
                self.overlayInstruction = ""
            }
            if wasSpeaking && !isSpeaking {
                self.onAgentStoppedSpeaking?()
            }
        }
    }
}

#endif
