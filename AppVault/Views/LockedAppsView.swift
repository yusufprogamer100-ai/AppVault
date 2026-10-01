import SwiftUI
import FamilyControls

struct LockedAppsView: View {
    @EnvironmentObject var lockManager: LockManager
    @EnvironmentObject var securityManager: SecurityManager
    @EnvironmentObject var themeManager: ThemeManager

    @State private var isPickerPresented = false
    @State private var showPinGate = false
    @State private var appToEdit: LockedAppConfig? = nil
    @State private var showCustomizer = false
    @State private var masterLock = false

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: themeManager.backgroundGradient, startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // MARK: Master Kilit Kartı
                        MasterLockCard(isActive: $masterLock) {
                            if masterLock {
                                lockManager.lockApplications()
                            } else {
                                lockManager.unlockApplications()
                            }
                        }

                        // MARK: Kilitli Uygulamalar
                        if lockManager.lockedApps.isEmpty {
                            EmptyStateView {
                                isPickerPresented = true
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("KİLİTLİ UYGULAMALAR")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white.opacity(0.4))
                                    .padding(.leading, 4)

                                ForEach(lockManager.lockedApps) { app in
                                    LockedAppCard(config: app,
                                        onEdit: {
                                            appToEdit = app
                                            showPinGate = true
                                        },
                                        onToggle: { isEnabled in
                                            var updated = app
                                            updated.isEnabled = isEnabled
                                            lockManager.updateLockedApp(updated)
                                        }
                                    )
                                }
                            }
                        }

                        // MARK: Add App Butonu
                        Button(action: { isPickerPresented = true }) {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 22))
                                Text("Uygulama Ekle")
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .opacity(0.5)
                            }
                            .foregroundColor(themeManager.accentColor)
                            .padding(18)
                            .background(themeManager.accentColor.opacity(0.12))
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(themeManager.accentColor.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .familyActivityPicker(isPresented: $isPickerPresented, selection: $lockManager.activitySelection)
                        .onChange(of: lockManager.activitySelection) { newVal in
                            for _ in newVal.applicationTokens {
                                let newApp = LockedAppConfig(
                                    displayName: "Yeni Uygulama",
                                    lockMethod: .zeroResponse
                                )
                                lockManager.addLockedApp(newApp)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Locked Apps")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { securityManager.lock() }) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            // PIN Kapısı → Özelleştirme Ekranı
            .sheet(isPresented: $showPinGate) {
                PinGateSheet(title: "Güvenlik Doğrulaması", subtitle: "Ayarları değiştirmek için PIN girin") {
                    showPinGate = false
                    showCustomizer = true
                }
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showCustomizer) {
                if let app = appToEdit {
                    AppCustomizerSheet(config: app)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: Master Kilit Kartı
struct MasterLockCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var isActive: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.red.opacity(0.2) : themeManager.accentColor.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: isActive ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 24))
                    .foregroundColor(isActive ? .red : themeManager.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(isActive ? "Kilitleme Aktif" : "Kilitleme Kapalı")
                    .font(.headline)
                    .foregroundColor(.white)
                Text(isActive ? "Tüm seçili uygulamalar bloke" : "Uygulamalar serbest")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isActive },
                set: { newVal in
                    isActive = newVal
                    onToggle()
                }
            ))
            .tint(themeManager.accentColor)
            .labelsHidden()
        }
        .padding(20)
        .background(isActive ? Color.red.opacity(0.08) : themeManager.cardBackground)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(isActive ? Color.red.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: Kilitli Uygulama Kartı
struct LockedAppCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let config: LockedAppConfig
    let onEdit: () -> Void
    let onToggle: (Bool) -> Void
    @State private var isEnabled: Bool

    init(config: LockedAppConfig, onEdit: @escaping () -> Void, onToggle: @escaping (Bool) -> Void) {
        self.config = config
        self.onEdit = onEdit
        self.onToggle = onToggle
        _isEnabled = State(initialValue: config.isEnabled)
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(themeManager.accentColor.opacity(0.15))
                    .frame(width: 50, height: 50)
                Image(systemName: config.disguisedIconSystemName.isEmpty ? "app.badge.fill" : config.disguisedIconSystemName)
                    .font(.system(size: 22))
                    .foregroundColor(themeManager.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(config.displayName)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.white)
                HStack(spacing: 6) {
                    Image(systemName: config.lockMethod.icon)
                        .font(.system(size: 10))
                    Text(config.lockMethod.displayName)
                        .font(.caption)
                }
                .foregroundColor(.white.opacity(0.45))
            }

            Spacer()

            Toggle("", isOn: $isEnabled)
                .tint(themeManager.accentColor)
                .labelsHidden()
                .onChange(of: isEnabled) { val in onToggle(val) }

            Button(action: onEdit) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(10)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(10)
            }
        }
        .padding(16)
        .background(themeManager.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}

// MARK: Boş Durum
struct EmptyStateView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.open.laptopcomputer")
                .font(.system(size: 52))
                .foregroundColor(themeManager.accentColor.opacity(0.5))
            Text("Henüz kilitlenen uygulama yok")
                .font(.headline)
                .foregroundColor(.white.opacity(0.5))
            Text("Aşağıdaki buton ile uygulama ekle")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }
}

// MARK: PIN Kapısı Sayfası
struct PinGateSheet: View {
    @EnvironmentObject var securityManager: SecurityManager
    @EnvironmentObject var themeManager: ThemeManager
    var title: String
    var subtitle: String
    var onSuccess: () -> Void

    @State private var input = ""
    @State private var shakeError = false

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
