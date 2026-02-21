import SwiftUI
import MWDATCore

@main
struct WApp: App {
    
    init() {
        do {
            try Wearables.configure()
        } catch {
            print("Failed to initialize Meta SDK: \(error)")
        }
        configureAppearance()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
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
