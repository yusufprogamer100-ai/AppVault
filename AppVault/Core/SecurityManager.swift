import Foundation

class SecurityManager: ObservableObject {
    static let shared = SecurityManager()
    
    @Published var savedPin: String = "0000"
    @Published var isUnlocked: Bool = false
    
    // Uygulama giriş PIN kontrolü
    func verifyPin(_ pin: String) -> Bool {
        return pin == savedPin
    }
    
    // PIN güncelleme
    func changePin(newPin: String) {
        guard newPin.count == 4 else { return }
        self.savedPin = newPin
    }
}
