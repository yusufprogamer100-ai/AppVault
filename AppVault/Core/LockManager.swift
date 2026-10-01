import Foundation
import FamilyControls
import ManagedSettings

enum LockMethod: String, CaseIterable, Identifiable, Codable {
    case zeroResponse = "Sifir Tepki"
    case fakeCrash = "Sahte Cokme"
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zeroResponse: return "Sıfır Tepki (Hiç Açılmaz)"
        case .fakeCrash: return "Sahte Çökme"
        }
    }
    var icon: String {
        switch self {
        case .zeroResponse: return "hand.raised.slash"
        case .fakeCrash: return "xmark.octagon"
        }
    }
}

struct LockedAppConfig: Identifiable, Codable {
    var id: String
    var displayName: String
    var disguisedName: String
    var disguisedIconSystemName: String
    var lockMethod: LockMethod
    var isEnabled: Bool

    init(id: String = UUID().uuidString,
         displayName: String,
         disguisedName: String = "",
         disguisedIconSystemName: String = "questionmark.app",
         lockMethod: LockMethod = .zeroResponse,
         isEnabled: Bool = true) {
        self.id = id
        self.displayName = displayName
        self.disguisedName = disguisedName
        self.disguisedIconSystemName = disguisedIconSystemName
        self.lockMethod = lockMethod
        self.isEnabled = isEnabled
    }
}

@MainActor
class LockManager: ObservableObject {
    static let shared = LockManager()

    private let store = ManagedSettingsStore()

    @Published var activitySelection = FamilyActivitySelection()
    @Published var isAuthorized: Bool = false
    @Published var isShieldActive: Bool = false
    @Published var lockedApps: [LockedAppConfig] = []

    init() {
        self.isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        loadLockedApps()
    }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            self.isAuthorized = (AuthorizationCenter.shared.authorizationStatus == .approved)
        } catch {
            self.isAuthorized = false
        }
    }

    func lockApplications() {
        let tokens = activitySelection.applicationTokens
        guard !tokens.isEmpty else { return }
        store.shield.applications = tokens
        self.isShieldActive = true
    }

    func unlockApplications() {
        store.shield.applications = nil
        self.isShieldActive = false
    }

    func addLockedApp(_ config: LockedAppConfig) {
        lockedApps.append(config)
        saveLockedApps()
    }

    func removeLockedApp(at offsets: IndexSet) {
        lockedApps.remove(atOffsets: offsets)
        saveLockedApps()
    }

    func updateLockedApp(_ config: LockedAppConfig) {
        if let idx = lockedApps.firstIndex(where: { $0.id == config.id }) {
            lockedApps[idx] = config
            saveLockedApps()
        }
    }

    private func saveLockedApps() {
        if let data = try? JSONEncoder().encode(lockedApps) {
            UserDefaults.standard.set(data, forKey: "locked_apps")
        }
    }

    private func loadLockedApps() {
        if let data = UserDefaults.standard.data(forKey: "locked_apps"),
           let apps = try? JSONDecoder().decode([LockedAppConfig].self, from: data) {
            lockedApps = apps
        }
    }
}
