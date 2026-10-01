import SwiftUI
import FamilyControls

// MARK: - Locked Apps Ana Sekmesi
struct LockedAppsView: View {
    @EnvironmentObject var lockManager: LockManager
    @EnvironmentObject var securityManager: SecurityManager
    @EnvironmentObject var themeManager: ThemeManager

    @State private var isPickerPresented = false
    @State private var masterShieldOn = false
    @State private var masterRestrictOn = false
    @State private var pendingEditId: String? = nil
    @State private var showPinGate = false
    @State private var showCustomizer = false
    @State private var showAdvancedLock = false

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: themeManager.backgroundGradient,
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {

                        // MARK: Screen Time İzin Uyarısı
                        if !lockManager.isAuthorized {
                            PermissionBanner()
                        }

                        // MARK: Master Kilit Paneli
                        MasterLockPanel(
                            shieldOn: $masterShieldOn,
                            restrictOn: $masterRestrictOn
                        )

                        // MARK: Gelişmiş Kilitleme Kısayolu
                        NavigationLink(destination: AdvancedLockView()) {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.red.opacity(0.18))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "xmark.shield.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.red)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Gelişmiş Kilitleme")
                                        .font(.subheadline).fontWeight(.semibold)
                                        .foregroundColor(.white)
                                    Text("Tam kısıtlama, zaman çizelgesi ve daha fazlası")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.45))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.3))
                            }
                            .padding(16)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(16)
                            .overlay(RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.red.opacity(0.2), lineWidth: 1))
                        }

                        // MARK: Uygulama Listesi
                        if lockManager.lockedApps.isEmpty {
                            EmptyLockedAppsView()
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                CustomSectionHeader(title: "KİLİTLİ UYGULAMALAR (\(lockManager.lockedApps.count))")

                                ForEach(lockManager.lockedApps) { app in
                                    LockedAppRow(
                                        config: app,
                                        onEdit: {
                                            pendingEditId = app.id
                                            showPinGate = true
                                        },
                                        onToggle: { enabled in
                                            var updated = app
                                            updated.isEnabled = enabled
                                            lockManager.updateLockedApp(updated)
                                            if enabled {
                                                lockManager.applyLock(method: app.lockMethod)
                                            }
                                        }
                                    )
                                }
                            }
                        }

                        // MARK: Uygulama Ekle Butonu
                        AddAppButton(isPickerPresented: $isPickerPresented)
                            .familyActivityPicker(
                                isPresented: $isPickerPresented,
                                selection: $lockManager.activitySelection
                            )
                            .onChange(of: lockManager.activitySelection) { sel in
                                // Gerçek seçimden yeni uygulama ekle
                                // Her token için bir config oluşturulur
                                if !sel.applicationTokens.isEmpty {
                                    let newApp = LockedAppConfig(
                                        displayName: "Seçilen Uygulama",
                                        lockMethod: .shield,
                                        isEnabled: false
                                    )
                                    lockManager.addLockedApp(newApp)
                                }
                            }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Locked Apps")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { securityManager.lock() }) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            // PIN Kapısı → Özelleştirici
            .sheet(isPresented: $showPinGate) {
                NavigationView {
                    ZStack {
                        LinearGradient(colors: themeManager.backgroundGradient,
                                       startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea()
                        PasscodeView(
                            title: "Güvenlik Doğrulaması",
                            subtitle: "Ayarları değiştirmek için PIN girin"
                        ) {
                            showPinGate = false
                            showCustomizer = true
                        }
                        .environmentObject(securityManager)
                        .environmentObject(themeManager)
                    }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("İptal") { showPinGate = false }
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
            }
            .sheet(isPresented: $showCustomizer) {
                if let id = pendingEditId,
                   let app = lockManager.lockedApps.first(where: { $0.id == id }) {
                    AppCustomizerSheet(config: app)
                        .environmentObject(lockManager)
                        .environmentObject(themeManager)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - İzin Uyarı Bandı
struct PermissionBanner: View {
    @EnvironmentObject var lockManager: LockManager
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        Button(action: { Task { await lockManager.requestAuthorization() } }) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Screen Time İzni Gerekiyor")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text("Kilitlemek için buraya dokun")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.orange.opacity(0.7))
            }
            .padding(16)
            .background(Color.orange.opacity(0.12))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1))
        }
    }
}

// MARK: - Master Kilit Paneli
struct MasterLockPanel: View {
    @EnvironmentObject var lockManager: LockManager
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var shieldOn: Bool
    @Binding var restrictOn: Bool

    var body: some View {
        VStack(spacing: 12) {
            CustomSectionHeader(title: "MASTER KİLİT")

            // Shield Kilidi
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(shieldOn ? 0.3 : 0.12))
                        .frame(width: 50, height: 50)
                    Image(systemName: "hand.raised.slash.fill")
                        .font(.system(size: 22))
                        .foregroundColor(shieldOn ? .orange : .white.opacity(0.4))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sıfır Tepki (Shield)")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.white)
                    Text("Uygulamaya basılınca tepki vermez")
                        .font(.caption).foregroundColor(.white.opacity(0.45))
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { shieldOn },
                    set: { val in
                        shieldOn = val
                        val ? lockManager.applyShieldLock() : lockManager.removeShieldLock()
                    }
                ))
                .tint(.orange)
                .labelsHidden()
            }
            .padding(16)
            .background(shieldOn ? Color.orange.opacity(0.08) : themeManager.cardBackground)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(shieldOn ? Color.orange.opacity(0.3) : Color.white.opacity(0.07), lineWidth: 1))

            // Gelişmiş Restrict Kilidi
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(restrictOn ? 0.3 : 0.12))
                        .frame(width: 50, height: 50)
                    Image(systemName: "xmark.shield.fill")
                        .font(.system(size: 22))
                        .foregroundColor(restrictOn ? .red : .white.opacity(0.4))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Gelişmiş Kilitleme")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.white)
                    Text("App Store'dan bile tamamen bloke")
                        .font(.caption).foregroundColor(.white.opacity(0.45))
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { restrictOn },
                    set: { val in
                        restrictOn = val
                        val ? lockManager.applyRestrictLock() : lockManager.removeRestrictLock()
                    }
                ))
                .tint(.red)
                .labelsHidden()
            }
            .padding(16)
            .background(restrictOn ? Color.red.opacity(0.08) : themeManager.cardBackground)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(restrictOn ? Color.red.opacity(0.3) : Color.white.opacity(0.07), lineWidth: 1))
        }
    }
}

// MARK: - Uygulama Satırı
struct LockedAppRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let config: LockedAppConfig
    let onEdit: () -> Void
    let onToggle: (Bool) -> Void
    @State private var enabled: Bool

    init(config: LockedAppConfig, onEdit: @escaping () -> Void, onToggle: @escaping (Bool) -> Void) {
        self.config = config
        self.onEdit = onEdit
        self.onToggle = onToggle
        _enabled = State(initialValue: config.isEnabled)
    }

    var methodColor: Color {
        config.lockMethod == .restrict ? .red : .orange
    }

    var body: some View {
        HStack(spacing: 14) {
            // İkon
            ZStack {
                RoundedRectangle(cornerRadius: 13)
                    .fill(themeManager.accentColor.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: config.disguisedIconSystemName.isEmpty
                      ? "app.badge.fill"
                      : config.disguisedIconSystemName)
                    .font(.system(size: 24))
                    .foregroundColor(themeManager.accentColor)
            }

            // Bilgi
            VStack(alignment: .leading, spacing: 4) {
                Text(config.displayName)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.white)
                HStack(spacing: 6) {
                    Image(systemName: config.lockMethod.icon)
                        .font(.system(size: 10))
                        .foregroundColor(methodColor)
                    Text(config.lockMethod.displayName)
                        .font(.caption)
                        .foregroundColor(methodColor.opacity(0.8))
                    if config.scheduleEnabled {
                        Text("• Zamanlı")
                            .font(.caption)
                            .foregroundColor(.blue.opacity(0.8))
                    }
                }
            }

            Spacer()

            Toggle("", isOn: $enabled)
                .tint(themeManager.accentColor)
                .labelsHidden()
                .onChange(of: enabled) { val in onToggle(val) }

            Button(action: onEdit) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(10)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(10)
            }
        }
        .padding(14)
        .background(themeManager.cardBackground)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(enabled ? themeManager.accentColor.opacity(0.2) : Color.white.opacity(0.06),
                    lineWidth: 1))
    }
}

// MARK: - Uygulama Ekle Butonu
struct AddAppButton: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var isPickerPresented: Bool

    var body: some View {
        Button(action: { isPickerPresented = true }) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(themeManager.accentColor)
                Text("Uygulama Seç ve Ekle")
                    .font(.headline)
                    .foregroundColor(themeManager.accentColor)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(themeManager.accentColor.opacity(0.5))
            }
            .padding(18)
            .background(themeManager.accentColor.opacity(0.1))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(themeManager.accentColor.opacity(0.25), lineWidth: 1))
        }
    }
}

// MARK: - Boş Durum
struct EmptyLockedAppsView: View {
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.open.laptopcomputer")
                .font(.system(size: 54))
                .foregroundColor(themeManager.accentColor.opacity(0.35))
            Text("Henüz uygulama eklenmedi")
                .font(.headline)
                .foregroundColor(.white.opacity(0.45))
            Text("Aşağıdaki butonla TikTok, Instagram\nveya istediğin uygulamayı seç.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}


