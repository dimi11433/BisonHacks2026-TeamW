#if canImport(UIKit)
import Foundation
import AVFoundation
import LiveKit
import Combine

@Observable
final class LiveKitManager: NSObject {

    // MARK: - Configuration
    static let tokenServerURL = "https://f10d-138-238-254-107.ngrok-free.app"

    // MARK: - Public State
    var isConnected = false
    var isConnecting = false
    var boundingBoxes: [BoundingBox] = []
    var localVideoTrack: VideoTrack?
    var connectionError: String?
    var isAgentSpeaking = false
    var onAgentStoppedSpeaking: (() -> Void)?

    // MARK: - Private
    private let room = Room()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init
    override init() {
        super.init()
        room.add(delegate: self)
    }

    // MARK: - Connect
    func connect() async {
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
            print("[LiveKit] Room connected. Enabling camera...")

            try await room.localParticipant.setCamera(enabled: true, captureOptions: CameraCaptureOptions(position: .back))
            print("[LiveKit] Camera enabled. Enabling mic...")

            try await room.localParticipant.setMicrophone(enabled: true)
            print("[LiveKit] Mic enabled. Checking video tracks...")

            if let pub = room.localParticipant.localVideoTracks.first,
               let videoTrack = pub.track as? VideoTrack {
                localVideoTrack = videoTrack
                print("[LiveKit] Local video track set.")
            } else {
                print("[LiveKit] No local video track found yet, waiting for delegate.")
            }

            isConnected = true
            print("[LiveKit] Fully connected!")
        } catch {
            connectionError = error.localizedDescription
            print("[LiveKit] ERROR: \(error)")
        }

        isConnecting = false
    }

    // MARK: - Disconnect
    func disconnect() async {
        await room.disconnect()
        isConnected = false
        localVideoTrack = nil
        boundingBoxes = []
    }

    // MARK: - Mic Control

    func setMicEnabled(_ enabled: Bool) async {
        try? await room.localParticipant.setMicrophone(enabled: enabled)
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
            if let box = try? JSONDecoder().decode(BoundingBox.self, from: data) {
                Task { @MainActor in
                    self.boundingBoxes = [box]
                }
            }
        }

        if topic == "ar_step" {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let animation = json["animation"] as? String,
               let instruction = json["instruction"] as? String {
                Task { @MainActor in
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootVC = windowScene.windows.first?.rootViewController,
                       let arVC = rootVC.findViewController(ofType: ARViewController.self) {
                        arVC.onStepReceived(animation: animation, instruction: instruction)
                    }
                }
            }
        }
    }

    nonisolated func room(_ room: Room, didDisconnect disconnectReason: DisconnectReason?) {
        Task { @MainActor in
            self.isConnected = false
            self.localVideoTrack = nil as VideoTrack?
            if let error {
                self.connectionError = error.localizedDescription
            }
        }
    }

    nonisolated func room(_ room: Room, participant: LocalParticipant, didPublishTrack publication: LocalTrackPublication) {
        if let videoTrack = publication.track as? VideoTrack {
            Task { @MainActor in
                self.localVideoTrack = videoTrack
            }
        }
    }

    nonisolated func room(_ room: Room, participant: Participant, didUpdateIsSpeaking isSpeaking: Bool) {
        guard participant is RemoteParticipant else { return }
        Task { @MainActor in
            let wasSpeaking = self.isAgentSpeaking
            self.isAgentSpeaking = isSpeaking
            if wasSpeaking && !isSpeaking {
                self.onAgentStoppedSpeaking?()
            }
        }
    }
}

// MARK: - UIViewController Helper
extension UIViewController {
    func findViewController<T: UIViewController>(ofType type: T.Type) -> T? {
        if let vc = self as? T { return vc }
        for child in children {
            if let found = child.findViewController(ofType: type) { return found }
        }
        if let presented = presentedViewController {
            return presented.findViewController(ofType: type)
        }
        return nil
    }
}

#endif