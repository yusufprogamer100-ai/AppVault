import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var lockManager: LockManager
    @EnvironmentObject var themeManager: ThemeManager
    var onComplete: () -> Void

    @State private var currentStep = 0
    @State private var isRequestingPermission = false

    var body: some View {
        ZStack {
            LinearGradient(colors: themeManager.backgroundGradient, startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Animasyonlu İkon
                ZStack {
                    Circle()
                        .fill(themeManager.accentColor.opacity(0.15))
                        .frame(width: 140, height: 140)
                    Circle()
                        .fill(themeManager.accentColor.opacity(0.08))
                        .frame(width: 180, height: 180)
                    Image(systemName: currentStep == 0 ? "lock.shield.fill" : "checkmark.shield.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(themeManager.accentColor)
                        
                }
                .padding(.bottom, 40)

                if currentStep == 0 {
                    welcomeStep
                } else {
                    permissionStep
                }

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 32)
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Text("AppVault'a Hoş Geldin")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text("Uygulamalarını gizle, kilitle ve özelleştir.\nHesap Makinesi görünümünde, tamamen gizli.")
                .font(.body)
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.bottom, 20)

            // Özellikler
            VStack(spacing: 14) {
                FeatureRow(icon: "lock.fill", color: .blue, title: "Uygulama Kilitleme", subtitle: "Seçtiğin uygulamaları tamamen bloke et")
                FeatureRow(icon: "eye.slash.fill", color: .purple, title: "Kamuflaj Sistemi", subtitle: "Hesap makinesi kılığında gizli kasa")
                FeatureRow(icon: "paintpalette.fill", color: .orange, title: "Tema Sistemi", subtitle: "5 farklı tema, tamamen özelleştirilebilir")
            }
            .padding(.bottom, 32)

            Button(action: { withAnimation(.spring()) { currentStep = 1 } }) {
                Text("Başlayalım →")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(themeManager.accentColor)
                    .cornerRadius(16)
            }
        }
    }

    private var permissionStep: some View {
        VStack(spacing: 20) {
            Text("Ekran Süresi İzni")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)

            Text("Uygulamaları kilitleyebilmek için\nApple Ekran Süresi iznine ihtiyaç var.\n\nSonraki adımda Apple'ın sistem penceresi açılacak — sadece onayla.")
                .font(.body)
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.bottom, 20)

            Button(action: {
                isRequestingPermission = true
                Task {
                    await lockManager.requestAuthorization()
                    isRequestingPermission = false
                    onComplete()
                }
            }) {
                HStack(spacing: 10) {
                    if isRequestingPermission {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark.shield.fill")
                    }
                    Text(isRequestingPermission ? "İzin isteniyor..." : "İzni Ver ve Başla")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(themeManager.accentColor)
                .cornerRadius(16)
            }
            .disabled(isRequestingPermission)

            Button("Şimdilik Geç") {
                onComplete()
            }
            .foregroundColor(.white.opacity(0.4))
            .font(.subheadline)
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.18))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()
        }
        .padding(14)
        .background(Color.white.opacity(0.06))
        .cornerRadius(14)
    }
}
