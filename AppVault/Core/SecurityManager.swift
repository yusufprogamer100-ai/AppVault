import Foundation
import FamilyControls

class SecurityManager: ObservableObject {
    static let shared = SecurityManager()

    @Published var isUnlocked: Bool = false

    private let pinKey = "app_vault_pin"

    var savedPin: String {
        get { UserDefaults.standard.string(forKey: pinKey) ?? "0000" }
        set { UserDefaults.standard.set(newValue, forKey: pinKey) }
    }

    func verifyPin(_ pin: String) -> Bool {
        return pin == savedPin
    }

    func changePin(to newPin: String) {
        guard newPin.count == 4 else { return }
        savedPin = newPin
    }

    func lock() {
        isUnlocked = false
    }
}
