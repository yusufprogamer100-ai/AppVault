import SwiftUI

// MARK: - Ortak Bölüm Başlığı
struct CustomSectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.white.opacity(0.38))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
    }
}

// MARK: - Bilgi Kartı
struct InfoCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let body: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(iconColor)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.white)
                Text(body)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .lineSpacing(4)
            }
        }
        .padding(16)
        .background(iconColor.opacity(0.07))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(iconColor.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Kart Bölümü Sarmalayıcısı
struct CardSection<Content: View>: View {
    @EnvironmentObject var themeManager: ThemeManager
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CustomSectionHeader(title: title)
            VStack(spacing: 0) { content }
                .padding(16)
                .background(themeManager.cardBackground)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1))
        }
    }
}

// MARK: - Özel Metin Alanı
struct CustomTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.55))
                .frame(width: 140, alignment: .leading)
            TextField(placeholder.isEmpty ? label : placeholder, text: $text)
                .font(.subheadline)
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Ayarlar Satırı
struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(iconColor.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundColor(iconColor)
                }
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.25))
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Bilgi Satırı
struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.55))
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(.white)
        }
    }
}
// MARK: - PIN Kapısı Sayfası
struct PinGateSheet: View {
    @EnvironmentObject var securityManager: SecurityManager
    @EnvironmentObject var themeManager: ThemeManager
    var title: String
    var subtitle: String
    var onSuccess: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: themeManager.backgroundGradient, startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            PasscodeView(title: title, subtitle: subtitle, onUnlockSuccess: onSuccess)
                .environmentObject(securityManager)
                .environmentObject(themeManager)
        }
    }
}
