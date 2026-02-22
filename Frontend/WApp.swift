import SwiftUI
import MWDATCore

@main
struct WApp: App {
    
    init() {
        do {
            try Wearables.configure()
            print("[Meta] SDK configured successfully")
        } catch {
            print("[Meta] Failed to initialize Meta SDK: \(error)")
        }
        
        // Dump MWDAT config from Info.plist for debugging
        if let mwdat = Bundle.main.infoDictionary?["MWDAT"] as? [String: Any] {
            print("[Meta] MWDAT config: \(mwdat)")
        } else {
            print("[Meta] WARNING: No MWDAT key found in Info.plist!")
        }
        if let urlTypes = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] {
            print("[Meta] URL Types: \(urlTypes)")
        } else {
            print("[Meta] WARNING: No CFBundleURLTypes found!")
        }
        if let queries = Bundle.main.infoDictionary?["LSApplicationQueriesSchemes"] as? [String] {
            print("[Meta] Query schemes: \(queries)")
        }
        
        configureAppearance()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    Task {
                        do {
                            let handled = try await Wearables.shared.handleUrl(url)
                            print("[Meta] URL handled: \(handled)")
                        } catch {
                            print("[Meta] URL handling error: \(error)")
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
