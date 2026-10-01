import SwiftUI
import FamilyControls

@main
struct AppVaultApp: App {
    @StateObject private var securityManager = SecurityManager.shared
    @StateObject private var lockManager = LockManager.shared
    
    var body: some Scene {
        WindowGroup {
            if securityManager.isUnlocked {
                MainDashboardView()
                    .environmentObject(securityManager)
                    .environmentObject(lockManager)
            } else {
                PasscodeView(title: "Güvenli Kasa", subtitle: "Devam etmek için 4 haneli PIN girin") {
                    securityManager.isUnlocked = true
                }
            }
        }
    }
}
