import SwiftUI
import MWDATCore

@main
struct WApp: App {
    
    init() {
        do {
            try Wearables.configure()
            print("[MWDAT] SDK configured successfully")
        } catch {
            print("[MWDAT] Failed to configure SDK: \(error)")
        }
        configureAppearance()
        
        let wearables = Wearables.shared
        print("[MWDAT] Registration state: \(wearables.registrationState)")
        print("[MWDAT] Devices: \(wearables.devices)")
        
        _ = wearables.addDevicesListener { ids in
            print("[MWDAT] Devices changed: \(ids)")
            for id in ids {
                if let device = wearables.deviceForIdentifier(id) {
                    print("[MWDAT]   -> \(device.name), link=\(device.linkState), type=\(device.deviceType())")
                }
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    print("[MWDAT] Received URL: \(url)")
                    Task {
                        do {
                            let handled = try await Wearables.shared.handleUrl(url)
                            print("[MWDAT] URL handled: \(handled), devices=\(Wearables.shared.devices)")
                        } catch {
                            print("[MWDAT] handleUrl error: \(error)")
                        }
                    }
                }
        }
    }
    
    private func configureAppearance() {
        #if canImport(UIKit)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        #endif
    }
}
