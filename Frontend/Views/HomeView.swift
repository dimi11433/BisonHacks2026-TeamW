import SwiftUI
import MWDATCore

struct HomeView: View {
    @State private var showAssembly = false
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0
    @State private var contentOpacity: Double = 0
    @State private var buttonOffset: CGFloat = 30
    @State private var glassesDetected = false
    @State private var registrationState: RegistrationState = .unavailable
    @State private var isRegistering = false
    @State private var registrationError: String?
    @State private var devicesListenerToken: (any AnyListenerToken)?
    @State private var registrationListenerToken: (any AnyListenerToken)?
    @State private var pollingTask: Task<Void, Never>?
    @State private var selectedCameraSource: CameraSource = .phone
    
    private let cyan = Color(hex: 0x00FFFF)
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0x0A0A0F),
                    Color(hex: 0x0D1117),
                    Color(hex: 0x0A0A0F)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            GridPatternView()
                .opacity(0.04)
                .ignoresSafeArea()
            
            FloatingParticlesView()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // MARK: - Logo + Branding
                VStack(spacing: 24) {
                    WLogoView()
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                    
                    VStack(spacing: 8) {
                        Text("W")
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.white, cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        +
                        Text(" Vision")
                            .font(.system(size: 40, weight: .ultraLight, design: .rounded))
                            .foregroundStyle(cyan.opacity(0.8))
                        
                        Text("See it. Ask it. Know it.")
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.top, 2)
                        
                        Text("Your AI-powered spatial guide")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .opacity(logoOpacity)
                }
                
                Spacer().frame(height: 30)
                
                // MARK: - Status Cards
                VStack(spacing: 12) {
                    Button {
                        if registrationState != .registered {
                            registerGlasses()
                        }
                    } label: {
                        StatusRow(
                            icon: "eyeglasses",
                            title: "Meta Ray-Ban",
                            subtitle: glassesSubtitle,
                            accentColor: glassesDetected ? cyan : .orange,
                            dotColor: glassesDetected ? .green : (registrationState == .registered ? .orange : .red)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    StatusRow(
                        icon: "camera.viewfinder",
                        title: "AR Vision",
                        subtitle: "Real-time spatial awareness",
                        accentColor: .green,
                        dotColor: .green
                    )
                    
                    StatusRow(
                        icon: "mic.badge.plus",
                        title: "Voice Control",
                        subtitle: "Just ask — hands-free interaction",
                        accentColor: .purple,
                        dotColor: .green
                    )
                }
                .padding(.horizontal, 24)
                .opacity(contentOpacity)
                
                Spacer().frame(height: 16)
                
                // MARK: - Camera Source Picker
                HStack(spacing: 0) {
                    cameraSourceOption(.phone)
                    cameraSourceOption(.glasses)
                }
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.06), lineWidth: 0.5)
                )
                .padding(.horizontal, 24)
                .opacity(contentOpacity)
                
                Spacer().frame(height: 36)
                
                // MARK: - Start Button
                Button {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        showAssembly = true
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                        
                        Text("Start Live")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(cyan, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(color: cyan.opacity(0.4), radius: 16, y: 8)
                }
                .padding(.horizontal, 24)
                .opacity(contentOpacity)
                .offset(y: buttonOffset)
                
                Spacer().frame(height: 14)
                
                Text("Point your camera at anything and just ask")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.25))
                    .opacity(contentOpacity)
                
                Spacer().frame(height: 36)
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showAssembly) {
            AssemblyView(preferredCameraSource: selectedCameraSource)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.1)) {
                logoScale = 1.0
                logoOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.4)) {
                contentOpacity = 1
                buttonOffset = 0
            }
            startGlassesDetection()
        }
        .onDisappear {
            pollingTask?.cancel()
            pollingTask = nil
            Task {
                await devicesListenerToken?.cancel()
                devicesListenerToken = nil
                await registrationListenerToken?.cancel()
                registrationListenerToken = nil
            }
        }
    }
    
    private var glassesSubtitle: String {
        if glassesDetected {
            return "Connected"
        }
        if let error = registrationError {
            return error
        }
        switch registrationState {
        case .registered:
            return "Registered — waiting for glasses"
        case .registering:
            return "Registering with Meta..."
        case .available:
            return isRegistering ? "Opening Meta AI..." : "Tap to connect with Meta"
        case .unavailable:
            return "Meta AI app required — tap to set up"
        @unknown default:
            return "Tap to set up"
        }
    }
    
    @ViewBuilder
    private func cameraSourceOption(_ source: CameraSource) -> some View {
        let isSelected = selectedCameraSource == source
        let isDisabled = source == .glasses && !glassesDetected

        Button {
            guard !isDisabled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCameraSource = source
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: source.icon)
                    .font(.system(size: 12, weight: .medium))
                Text(source.rawValue)
                    .font(.system(.caption, design: .rounded, weight: .medium))
            }
            .foregroundStyle(isDisabled ? .white.opacity(0.2) : isSelected ? .black : .white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                isSelected ? cyan : Color.clear,
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
        .padding(2)
    }

    private func registerGlasses() {
        guard !isRegistering else {
            print("[Meta] Already registering, skipping")
            return
        }
        registrationError = nil
        print("[Meta] Current registration state: \(registrationState)")
        
        #if canImport(UIKit)
        if let metaAIURL = URL(string: "fb-viewapp://") {
            let canOpen = UIApplication.shared.canOpenURL(metaAIURL)
            print("[Meta] Can open fb-viewapp:// = \(canOpen)")
            if !canOpen {
                registrationError = "Meta AI app not found — install from App Store"
                return
            }
        }
        #endif
        
        isRegistering = true
        Task { @MainActor in
            do {
                print("[Meta] Calling startRegistration()...")
                try await Wearables.shared.startRegistration()
                print("[Meta] Registration call completed successfully")
            } catch let error as RegistrationError {
                print("[Meta] Registration error: \(error) — \(error.description)")
                switch error {
                case .metaAINotInstalled:
                    registrationError = "Install Meta AI app first"
                case .alreadyRegistered:
                    registrationError = nil
                case .configurationInvalid:
                    registrationError = "Enable Developer Mode in Meta AI settings"
                case .networkUnavailable:
                    registrationError = "No network — try again"
                default:
                    registrationError = "Error: \(error.description)"
                }
            } catch {
                print("[Meta] Unexpected error: \(error)")
                registrationError = "Error: \(error.localizedDescription)"
            }
            isRegistering = false
        }
    }
    
    private func startGlassesDetection() {
        let wearables = Wearables.shared
        
        registrationState = wearables.registrationState
        print("[Meta] Initial registration state: \(registrationState) (raw: \(registrationState.rawValue))")
        print("[Meta] Initial devices count: \(wearables.devices.count)")
        if !wearables.devices.isEmpty {
            print("[Meta] Device IDs: \(wearables.devices)")
        }
        
        registrationListenerToken = wearables.addRegistrationStateListener { state in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.registrationState = state
                }
                print("[Meta] Registration state changed: \(state)")
                if state == .registered {
                    self.updateGlassesState(deviceIds: wearables.devices, wearables: wearables)
                }
            }
        }
        
        updateGlassesState(deviceIds: wearables.devices, wearables: wearables)
        
        devicesListenerToken = wearables.addDevicesListener { ids in
            Task { @MainActor in
                self.updateGlassesState(deviceIds: ids, wearables: wearables)
            }
        }
        
        pollingTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }
                self.updateGlassesState(deviceIds: wearables.devices, wearables: wearables)
            }
        }
    }
    
    private func updateGlassesState(deviceIds: [String], wearables: any WearablesInterface) {
        if let firstId = deviceIds.first,
           let device = wearables.deviceForIdentifier(firstId) {
            let connected = device.linkState == .connected
            withAnimation(.easeInOut(duration: 0.3)) {
                glassesDetected = connected
                if connected && selectedCameraSource == .phone {
                    selectedCameraSource = .glasses
                }
                if !connected && selectedCameraSource == .glasses {
                    selectedCameraSource = .phone
                }
            }
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                glassesDetected = false
                if selectedCameraSource == .glasses {
                    selectedCameraSource = .phone
                }
            }
        }
    }
}

// MARK: - Status Row

private struct StatusRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let accentColor: Color
    var dotColor: Color = .green
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(accentColor)
                .frame(width: 36, height: 36)
                .background(accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                
                Text(subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }
            
            Spacer()
            
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.06), lineWidth: 0.5)
                )
        }
    }
}

// MARK: - Grid Pattern

private struct GridPatternView: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 30
            for x in stride(from: 0, to: size.width, by: spacing) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.white), lineWidth: 0.5)
            }
            for y in stride(from: 0, to: size.height, by: spacing) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.white), lineWidth: 0.5)
            }
        }
    }
}

#Preview {
    HomeView()
}
