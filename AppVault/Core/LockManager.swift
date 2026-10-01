import Foundation
import FamilyControls
import ManagedSettings

enum LockMethod: String, CaseIterable, Identifiable {
    case zeroResponse = "1. Yöntem: Sıfır Tepki (Hiç Açılmaz)"
    case fakeCrash = "2. Yöntem: Sahte Çökme (Açılır gibi olup kapanır)"
    
    var id: String { self.rawValue }
}

struct AppCustomization: Identifiable, Codable {
    var id: String
    var originalName: String
    var disguisedName: String
    var disguisedIconName: String
    var lockMethod: String
}

@MainActor
class LockManager: ObservableObject {
    static let shared = LockManager()
    
    private let store = ManagedSettingsStore()
    
    @Published var activitySelection = FamilyActivitySelection()
    @Published var isAuthorized: Bool = false
    @Published var isShieldActive: Bool = false
    
    // Özelleştirilen uygulamaların listesi (Ad, İkon, Kilit Türü)
    @Published var customConfigurations: [String: AppCustomization] = [:]
    
    init() {
        // Başlangıçta yetki durumunu kontrol et
        self.isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
    }
    
    // Apple Screen Time / FamilyControls izni iste
    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            self.isAuthorized = (AuthorizationCenter.shared.authorizationStatus == .approved)
        } catch {
            print("Screen Time Yetki Hatası: \(error.localizedDescription)")
            self.isAuthorized = false
        }
    }
    
    // Uygulamaları kilitle (1. Yöntem: Sıfır Tepki Shield)
    func lockApplications() {
        let tokens = activitySelection.applicationTokens
        guard !tokens.isEmpty else {
            store.shield.applications = nil
            isShieldActive = false
            return
        }
        
        // ManagedSettingsStore ile uygulamaların önüne tam perde çekiyoruz
        store.shield.applications = tokens
        self.isShieldActive = true
    }
    
    // Kilitleri kaldır
    func unlockApplications() {
        store.shield.applications = nil
        self.isShieldActive = false
    }
}
