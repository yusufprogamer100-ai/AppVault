import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity

// MARK: - Kilitleme Yöntemi
enum LockMethod: String, CaseIterable, Identifiable, Codable {
    case shield = "shield"
    case restrict = "restrict"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .shield:   return "Sıfır Tepki (Shield)"
        case .restrict: return "Gelişmiş Kilitleme (Kısıtlama)"
        }
    }
    var description: String {
        switch self {
        case .shield:
            return "Uygulamaya basıldığında hiç tepki vermez. Siyah perde çıkar."
        case .restrict:
            return "Uygulama ana ekrandan, App Store'dan ve her yerden tamamen kaybolur. \"Restrictions enabled\" mesajı çıkar."
        }
    }
    var icon: String {
        switch self {
        case .shield:   return "hand.raised.slash.fill"
        case .restrict: return "xmark.shield.fill"
        }
    }
    var color: String {
        switch self {
        case .shield:   return "orange"
        case .restrict: return "red"
        }
    }
}

// MARK: - Kilitli Uygulama Konfigürasyonu
struct LockedAppConfig: Identifiable, Codable {
    var id: String
    var displayName: String
    var disguisedName: String
    var disguisedIconSystemName: String
    var lockMethod: LockMethod
    var isEnabled: Bool

    // Gelişmiş Kilitleme: Zaman Çizelgesi
    var scheduleEnabled: Bool
    var lockHour: Int      // Kilitlenme saati (örn. 22 = 22:00)
    var lockMinute: Int
    var unlockHour: Int    // Açılma saati (örn. 12 = 12:00)
    var unlockMinute: Int

    init(
        id: String = UUID().uuidString,
        displayName: String,
        disguisedName: String = "",
        disguisedIconSystemName: String = "app.fill",
        lockMethod: LockMethod = .shield,
        isEnabled: Bool = true,
        scheduleEnabled: Bool = false,
        lockHour: Int = 22,
        lockMinute: Int = 0,
        unlockHour: Int = 12,
        unlockMinute: Int = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.disguisedName = disguisedName
        self.disguisedIconSystemName = disguisedIconSystemName
        self.lockMethod = lockMethod
        self.isEnabled = isEnabled
        self.scheduleEnabled = scheduleEnabled
        self.lockHour = lockHour
        self.lockMinute = lockMinute
        self.unlockHour = unlockHour
        self.unlockMinute = unlockMinute
    }
}

// MARK: - Lock Manager
@MainActor
class LockManager: ObservableObject {
    static let shared = LockManager()

    private let store = ManagedSettingsStore()

    @Published var activitySelection = FamilyActivitySelection()
    @Published var isAuthorized: Bool = false
    @Published var isShieldActive: Bool = false
    @Published var isRestrictActive: Bool = false
    @Published var lockedApps: [LockedAppConfig] = []

    init() {
        self.isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        loadLockedApps()
    }

    // MARK: FamilyControls İzni
    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            self.isAuthorized = (AuthorizationCenter.shared.authorizationStatus == .approved)
        } catch {
            self.isAuthorized = false
        }
    }

    // MARK: Shield Kilitleme (Sıfır Tepki)
    func applyShieldLock() {
        let tokens = activitySelection.applicationTokens
        guard !tokens.isEmpty else { return }
        store.shield.applications = tokens
        isShieldActive = true
    }

    func removeShieldLock() {
        store.shield.applications = nil
        isShieldActive = false
    }

    // MARK: Gelişmiş Kilitleme — applicationRestrictions
    // Bu yöntem uygulamayı tamamen bloke eder. App Store dahil her yerden kaybolur.
    // "Restrictions enabled: certain apps features or services cant be seen or used" mesajı çıkar.
    func applyRestrictLock() {
        let tokens = activitySelection.applicationTokens
        guard !tokens.isEmpty else { return }
        // applicationRestrictions ile tamamen kısıtla
        store.application.blockedApplications = tokens
        isRestrictActive = true
    }

    func removeRestrictLock() {
        store.application.blockedApplications = nil
        isRestrictActive = false
    }

    // MARK: Tüm Kilitleri Kaldır
    func unlockAll() {
        store.shield.applications = nil
        store.application.blockedApplications = nil
        isShieldActive = false
        isRestrictActive = false
    }

    // MARK: Seçime Göre Kilitle / Aç
    func applyLock(method: LockMethod) {
        switch method {
        case .shield:   applyShieldLock()
        case .restrict: applyRestrictLock()
        }
    }

    // MARK: Zaman Çizelgesi (DeviceActivity)
    func scheduleAutoLock(config: LockedAppConfig) {
        guard config.scheduleEnabled else { return }
        let center = DeviceActivityCenter()
        let activityName = DeviceActivityName("vault.schedule.\(config.id)")

        let lockComponents = DateComponents(hour: config.lockHour, minute: config.lockMinute)
        let unlockComponents = DateComponents(hour: config.unlockHour, minute: config.unlockMinute)

        let schedule = DeviceActivitySchedule(
            intervalStart: lockComponents,
            intervalEnd: unlockComponents,
            repeats: true
        )

        do {
            try center.startMonitoring(activityName, during: schedule)
        } catch {
            print("DeviceActivity schedule hatası: \(error)")
        }
    }

    func cancelSchedule(config: LockedAppConfig) {
        let center = DeviceActivityCenter()
        let activityName = DeviceActivityName("vault.schedule.\(config.id)")
        center.stopMonitoring([activityName])
    }

    // MARK: Kalıcı Kayıt
    func addLockedApp(_ config: LockedAppConfig) {
        lockedApps.append(config)
        saveLockedApps()
    }

    func removeLockedApp(id: String) {
        lockedApps.removeAll { $0.id == id }
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
            UserDefaults.standard.set(data, forKey: "locked_apps_v2")
        }
    }

    private func loadLockedApps() {
        if let data = UserDefaults.standard.data(forKey: "locked_apps_v2"),
           let apps = try? JSONDecoder().decode([LockedAppConfig].self, from: data) {
            lockedApps = apps
        }
    }
}
