import SwiftUI
import FamilyControls

@main
struct AppVaultApp: App {
    @StateObject private var securityManager = SecurityManager.shared
    @StateObject private var lockManager = LockManager.shared
    @StateObject private var themeManager = ThemeManager.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if securityManager.isUnlocked {
                    ContentRootView()
                        .environmentObject(securityManager)
                        .environmentObject(lockManager)
                        .environmentObject(themeManager)
                } else {
                    CalculatorView()
                        .environmentObject(securityManager)
                        .environmentObject(themeManager)
                }
            }
            .preferredColorScheme(themeManager.colorScheme)
            .tint(themeManager.accentColor)
        }
    }
}
