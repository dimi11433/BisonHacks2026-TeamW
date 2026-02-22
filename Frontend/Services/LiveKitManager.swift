#if canImport(UIKit)
import Foundation
import AVFoundation
import LiveKit
import Combine
import UIKit

@Observable
final class LiveKitManager: NSObject {

    // MARK: - Configuration
    // Update this after starting ngrok: `ngrok http 3001`
    static var tokenServerURL = "https://f10d-138-238-254-107.ngrok-free.app"

    // MARK: - Public State
    var isConnected = false
    var isConnecting = false
    var boundingBoxes: [BoundingBox] = []
    var activeOverlays: [OverlayItem] = []
    var activeAnimation: String? = nil
    var animationInstruction: String = ""
    var localVideoTrack: VideoTrack?
    var connectionError: String?
    var isAgentSpeaking = false
    var usingGlasses = false
    var onAgentStoppedSpeaking: (() -> Void)?
    var onGlassesDisconnected: (() -> Void)?
    var onBoundingBoxReceived: (() -> Void)?

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
        boundingBoxes = []
        activeOverlays = []
        activeAnimation = nil
        animationInstruction = ""
    }

    // MARK: - Mic Control
    func setMicEnabled(_ enabled: Bool) async {
        do {
            try await room.localParticipant.setMicrophone(enabled: enabled)
        } catch {
            print("[LiveKit] Mic error: \(error)")
        }
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

        if topic == "bounding_box" {
            let capturedData = data
            Task { @MainActor in
                guard let box = try? JSONDecoder().decode(BoundingBox.self, from: capturedData) else { return }
                self.boundingBoxes.append(box)
                self.onBoundingBoxReceived?()
            }
        }

        if topic == "ar_overlay" {
            let capturedData = data
            Task { @MainActor in
                guard let json = try? JSONSerialization.jsonObject(with: capturedData) as? [String: Any],
                      let items = json["overlays"] as? [[String: Any]] else { return }
                self.activeOverlays = items.compactMap { dict in
                    guard let itemData = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                    return try? JSONDecoder().decode(OverlayItem.self, from: itemData)
                }
            }
        }

        if topic == "ar_animation" {
            let capturedData = data
            Task { @MainActor in
                guard let json = try? JSONSerialization.jsonObject(with: capturedData) as? [String: Any],
                      let name = json["animation"] as? String else { return }
                self.activeAnimation = name
                self.animationInstruction = json["instruction"] as? String ?? ""
            }
        }

        if topic == "ar_clear" {
            Task { @MainActor in
                self.activeOverlays = []
                self.activeAnimation = nil
                self.animationInstruction = ""
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
                self.boundingBoxes = []
                self.activeOverlays = []
                self.activeAnimation = nil
                self.animationInstruction = ""
            }
            if wasSpeaking && !isSpeaking {
                self.onAgentStoppedSpeaking?()
            }
        }
    }
}

#endif