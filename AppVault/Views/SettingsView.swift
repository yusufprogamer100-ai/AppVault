import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var securityManager: SecurityManager
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var lockManager: LockManager

    @State private var showChangePinSheet = false
    @State private var showPinVerify = false

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: themeManager.backgroundGradient, startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // MARK: Uygulama Bilgisi
                        HStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(themeManager.accentColor.opacity(0.18))
                                    .frame(width: 64, height: 64)
                                Image(systemName: "lock.shield.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(themeManager.accentColor)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("AppVault")
                                    .font(.title3).fontWeight(.bold)
                                    .foregroundColor(.white)
                                Text("Hesap Makinesi olarak gizlenmiş")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.4))
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(lockManager.isAuthorized ? Color.green : Color.orange)
                                        .frame(width: 7, height: 7)
                                    Text(lockManager.isAuthorized ? "Screen Time İzni Var" : "İzin Gerekiyor")
                                        .font(.caption2)
                                        .foregroundColor(lockManager.isAuthorized ? .green : .orange)
                                }
                            }
                            Spacer()
                        }
                        .padding(20)
                        .background(themeManager.cardBackground)
                        .cornerRadius(20)
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.07), lineWidth: 1))

                        // MARK: Tema
                        CardSection(title: "GÖRÜNÜM") {
                            VStack(spacing: 14) {
                                ForEach(AppTheme.allCases) { theme in
                                    Button(action: { withAnimation(.spring()) { themeManager.currentTheme = theme } }) {
                                        HStack(spacing: 14) {
                                            Circle()
                                                .fill(theme.accentColor)
                                                .frame(width: 28, height: 28)
                                            Text(theme.rawValue)
                                                .font(.subheadline)
                                                .foregroundColor(.white)
                                            Spacer()
                                            if themeManager.currentTheme == theme {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(themeManager.accentColor)
                                            }
                                        }
                                    }
                                    if theme != AppTheme.allCases.last {
                                        Divider().background(Color.white.opacity(0.08))
                                    }
                                }
                            }
                        }

                        // MARK: Güvenlik
                        CardSection(title: "GÜVENLİK") {
                            VStack(spacing: 0) {
                                SettingsRow(icon: "key.fill", iconColor: .orange, title: "PIN Kodunu Değiştir") {
                                    showPinVerify = true
                                }

                                Divider().background(Color.white.opacity(0.08)).padding(.leading, 56)

                                SettingsRow(icon: "rectangle.portrait.and.arrow.right", iconColor: .red, title: "Hesap Makinesine Dön") {
                                    withAnimation(.spring()) { securityManager.lock() }
                                }
                            }
                        }

                        // MARK: Screen Time
                        if !lockManager.isAuthorized {
                            CardSection(title: "EKRAN SÜRESİ") {
                                Button(action: {
                                    Task { await lockManager.requestAuthorization() }
                                }) {
                                    HStack {
                                        Image(systemName: "person.badge.shield.checkmark.fill")
                                            .foregroundColor(.orange)
                                        Text("Screen Time İzni Ver")
                                            .font(.subheadline).fontWeight(.medium)
                                            .foregroundColor(.white)
                                        Spacer()
                                        Image(systemName: "arrow.right.circle")
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                        }

                        // MARK: Hakkında
                        CardSection(title: "HAKKINDA") {
                            VStack(spacing: 12) {
                                InfoRow(label: "Versiyon", value: "2.0.0")
                                Divider().background(Color.white.opacity(0.08))
                                InfoRow(label: "Geliştirici", value: "AppVault Team")
                                Divider().background(Color.white.opacity(0.08))
                                InfoRow(label: "Platform", value: "iOS 16+")
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.large)
            // PIN Doğrula → Sonra PIN Değiştir
            .sheet(isPresented: $showPinVerify) {
                PinGateSheet(title: "Mevcut PIN'i Doğrula", subtitle: "Önce mevcut kodunu gir") {
                    showPinVerify = false
                    showChangePinSheet = true
                }
                .environmentObject(securityManager)
                .environmentObject(themeManager)
            }
            .sheet(isPresented: $showChangePinSheet) {
                ChangePinView()
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct ChangePinView: View {
    @EnvironmentObject var securityManager: SecurityManager
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @State private var newPin = ""
    @State private var confirmPin = ""
    @State private var step = 0
    @State private var errorMsg = ""

    var body: some View {
        ZStack {
            LinearGradient(colors: themeManager.backgroundGradient, startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            PasscodeView(
                title: step == 0 ? "Yeni PIN Gir" : "Tekrar Gir",
                subtitle: step == 0 ? "4 haneli yeni PIN'ini belirle" : "Aynı PIN'i tekrar gir",
                onUnlockSuccess: {
                    // Bu PIN değiştirme akışında bu çağrılmayacak (PasscodeView bu akış için uygun değil, ama placeholder olarak kalsın)
                }
            )
            .environmentObject(securityManager)
            .environmentObject(themeManager)

            // Uyarı mesajı
            if !errorMsg.isEmpty {
                VStack {
                    Spacer()
                    Text(errorMsg)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .padding()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("İptal") { dismiss() }
            }
        }
    }
}
