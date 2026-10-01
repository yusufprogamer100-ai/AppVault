import Foundation
import SwiftUI

// Tema renkleri
enum AppTheme: String, CaseIterable, Identifiable {
    case dark = "Karanlık"
    case light = "Aydınlık"
    case midnight = "Gece Yarısı"
    case aurora = "Aurora Mor"
    case crimson = "Kırmızı"

    var id: String { rawValue }

    var accentColor: Color {
        switch self {
        case .dark: return .blue
        case .light: return .blue
        case .midnight: return Color(red: 0.4, green: 0.8, blue: 1.0)
        case .aurora: return Color(red: 0.7, green: 0.3, blue: 1.0)
        case .crimson: return Color(red: 1.0, green: 0.2, blue: 0.3)
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark, .midnight, .aurora, .crimson: return .dark
        case .light: return .light
        }
    }

    var backgroundGradient: [Color] {
        switch self {
        case .dark: return [Color(red: 0.08, green: 0.08, blue: 0.12), Color(red: 0.05, green: 0.05, blue: 0.08)]
        case .light: return [Color(red: 0.95, green: 0.97, blue: 1.0), Color(red: 0.88, green: 0.92, blue: 0.98)]
        case .midnight: return [Color(red: 0.04, green: 0.06, blue: 0.16), Color(red: 0.02, green: 0.03, blue: 0.10)]
        case .aurora: return [Color(red: 0.08, green: 0.04, blue: 0.18), Color(red: 0.04, green: 0.02, blue: 0.10)]
        case .crimson: return [Color(red: 0.16, green: 0.04, blue: 0.06), Color(red: 0.08, green: 0.02, blue: 0.04)]
        }
    }

    var cardBackground: Color {
        switch self {
        case .light: return Color(red: 1, green: 1, blue: 1).opacity(0.85)
        default: return Color.white.opacity(0.07)
        }
    }
}

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var currentTheme: AppTheme = .dark {
        didSet { UserDefaults.standard.set(currentTheme.rawValue, forKey: "selectedTheme") }
    }

    var accentColor: Color { currentTheme.accentColor }
    var colorScheme: ColorScheme? { currentTheme.colorScheme }
    var backgroundGradient: [Color] { currentTheme.backgroundGradient }
    var cardBackground: Color { currentTheme.cardBackground }

    init() {
        if let saved = UserDefaults.standard.string(forKey: "selectedTheme"),
           let theme = AppTheme(rawValue: saved) {
            currentTheme = theme
        }
    }
}
