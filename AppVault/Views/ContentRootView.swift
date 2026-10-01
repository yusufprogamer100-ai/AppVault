import SwiftUI

struct ContentRootView: View {
    @EnvironmentObject var securityManager: SecurityManager
    @EnvironmentObject var lockManager: LockManager
    @EnvironmentObject var themeManager: ThemeManager
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "onboarding_done")
    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            LinearGradient(colors: themeManager.backgroundGradient,
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if showOnboarding {
                OnboardingView {
                    UserDefaults.standard.set(true, forKey: "onboarding_done")
                    withAnimation(.spring()) { showOnboarding = false }
                }
                .environmentObject(lockManager)
                .environmentObject(themeManager)
            } else {
                TabView(selection: $selectedTab) {
                    LockedAppsView()
                        .environmentObject(securityManager)
                        .environmentObject(lockManager)
                        .environmentObject(themeManager)
                        .tabItem {
                            Label("Kilitli", systemImage: selectedTab == 0 ? "lock.shield.fill" : "lock.shield")
                        }
                        .tag(0)

                    SettingsView()
                        .environmentObject(securityManager)
                        .environmentObject(lockManager)
                        .environmentObject(themeManager)
                        .tabItem {
                            Label("Ayarlar", systemImage: selectedTab == 1 ? "gearshape.2.fill" : "gearshape.2")
                        }
                        .tag(1)
                }
                .tint(themeManager.accentColor)
            }
        }
    }
}
