import SwiftUI

// MARK: - Gelişmiş Kilitleme Sekmesi
struct AdvancedLockView: View {
    @EnvironmentObject var lockManager: LockManager
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var securityManager: SecurityManager
    @Environment(\.dismiss) var dismiss

    @State private var globalRestrictOn = false
    @State private var selectedApp: LockedAppConfig? = nil
    @State private var showScheduleEditor = false

    var body: some View {
        ZStack {
            LinearGradient(colors: themeManager.backgroundGradient,
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {

                    // MARK: Açıklama Kartı
                    InfoCard(
                        icon: "xmark.shield.fill",
                        iconColor: .red,
                        title: "Gelişmiş Kilitleme Nedir?",
                        descriptionText: "Seçilen uygulamayı Ana Ekran, App Store ve Spotlight dahil her yerden tamamen kaldırır.\n\nKilitli uygulama açılmaya çalışıldığında:\n\"Restrictions enabled: certain apps features or services can't be seen or used\" mesajı görünür."
                    )

                    // MARK: Global Kısıtlama Anahtarı
                    VStack(spacing: 10) {
                        CustomSectionHeader(title: "MASTER GELİŞMİŞ KİLİTLEME")

                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(Color.red.opacity(globalRestrictOn ? 0.25 : 0.1))
                                    .frame(width: 52, height: 52)
                                Image(systemName: globalRestrictOn ? "xmark.shield.fill" : "xmark.shield")
                                    .font(.system(size: 24))
                                    .foregroundColor(globalRestrictOn ? .red : .white.opacity(0.4))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(globalRestrictOn ? "Gelişmiş Kilitleme Aktif" : "Gelişmiş Kilitleme Kapalı")
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Text(globalRestrictOn ? "Tüm seçili uygulamalar tam kısıtlamada" : "Uygulamalar erişilebilir durumda")
                                    .font(.caption).foregroundColor(.white.opacity(0.45))
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { globalRestrictOn },
                                set: { val in
                                    globalRestrictOn = val
                                    val ? lockManager.applyRestrictLock() : lockManager.removeRestrictLock()
                                }
                            ))
                            .tint(.red)
                            .labelsHidden()
                        }
                        .padding(18)
                        .background(globalRestrictOn ? Color.red.opacity(0.08) : themeManager.cardBackground)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .stroke(globalRestrictOn ? Color.red.opacity(0.35) : Color.white.opacity(0.07), lineWidth: 1))
                    }

                    // MARK: Uygulama Bazlı Zaman Çizelgesi
                    if !lockManager.lockedApps.isEmpty {
                        VStack(spacing: 10) {
                            CustomSectionHeader(title: "UYGULAMA BAZLI ZAMAN ÇİZELGESİ")

                            ForEach($lockManager.lockedApps) { $app in
                                ScheduleAppRow(config: $app, onEdit: {
                                    selectedApp = app
                                    showScheduleEditor = true
                                })
                            }
                        }
                    }

                    // MARK: Güvenlik Ayarları
                    VStack(spacing: 10) {
                        CustomSectionHeader(title: "GELİŞMİŞ SEÇENEKLER")

                        VStack(spacing: 0) {
                            AdvancedOptionRow(
                                icon: "clock.badge.xmark",
                                iconColor: .purple,
                                title: "Varsayılan Kilit Süresi",
                                subtitle: "Uygulama açıkken otomatik kilitleme",
                                destination: AnyView(AutoLockTimerView())
                            )
                            Divider().background(Color.white.opacity(0.07)).padding(.leading, 56)
                            AdvancedOptionRow(
                                icon: "bell.badge.fill",
                                iconColor: .yellow,
                                title: "Kilit Bildirimleri",
                                subtitle: "Kilitlenince bildirim gönder",
                                destination: AnyView(NotificationSettingsView())
                            )
                            Divider().background(Color.white.opacity(0.07)).padding(.leading, 56)
                            AdvancedOptionRow(
                                icon: "eye.slash.fill",
                                iconColor: .blue,
                                title: "Gizli Mod",
                                subtitle: "Uygulama listesinden AppVault'u gizle",
                                destination: AnyView(StealthModeView())
                            )
                        }
                        .padding(16)
                        .background(themeManager.cardBackground)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.07), lineWidth: 1))
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("Gelişmiş Kilitleme")
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(false)
        .sheet(isPresented: $showScheduleEditor) {
            if let app = selectedApp {
                ScheduleEditorView(config: Binding(
                    get: { lockManager.lockedApps.first(where: { $0.id == app.id }) ?? app },
                    set: { lockManager.updateLockedApp($0) }
                ))
                .environmentObject(themeManager)
                .environmentObject(lockManager)
            }
        }
    }
}

// MARK: - Zaman Çizelgesi Uygulama Satırı
struct ScheduleAppRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var lockManager: LockManager
    @Binding var config: LockedAppConfig
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(themeManager.accentColor.opacity(0.14))
                    .frame(width: 46, height: 46)
                Image(systemName: config.disguisedIconSystemName.isEmpty ? "app.fill" : config.disguisedIconSystemName)
                    .font(.system(size: 20))
                    .foregroundColor(themeManager.accentColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(config.displayName)
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundColor(.white)
                if config.scheduleEnabled {
                    Text("Kilit: \(String(format: "%02d:%02d", config.lockHour, config.lockMinute)) — Aç: \(String(format: "%02d:%02d", config.unlockHour, config.unlockMinute))")
                        .font(.caption)
                        .foregroundColor(.blue.opacity(0.9))
                } else {
                    Text("Zaman çizelgesi kapalı")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.35))
                }
            }
            Spacer()
            Toggle("", isOn: $config.scheduleEnabled)
                .tint(.blue)
                .labelsHidden()
                .onChange(of: config.scheduleEnabled) { val in
                    lockManager.updateLockedApp(config)
                    if val { lockManager.scheduleAutoLock(config: config) }
                    else { lockManager.cancelSchedule(config: config) }
                }
            Button(action: onEdit) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.blue.opacity(0.7))
                    .padding(10)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(10)
            }
        }
        .padding(14)
        .background(themeManager.cardBackground)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(config.scheduleEnabled ? Color.blue.opacity(0.25) : Color.white.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Zaman Çizelgesi Düzenleyici
struct ScheduleEditorView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var lockManager: LockManager
    @Environment(\.dismiss) var dismiss
    @Binding var config: LockedAppConfig

    @State private var lockTime: Date
    @State private var unlockTime: Date

    init(config: Binding<LockedAppConfig>) {
        _config = config
        var comps = DateComponents()
        comps.hour = config.wrappedValue.lockHour
        comps.minute = config.wrappedValue.lockMinute
        let cal = Calendar.current
        _lockTime = State(initialValue: cal.date(from: comps) ?? Date())

        var uComps = DateComponents()
        uComps.hour = config.wrappedValue.unlockHour
        uComps.minute = config.wrappedValue.unlockMinute
        _unlockTime = State(initialValue: cal.date(from: uComps) ?? Date())
    }

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: themeManager.backgroundGradient,
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {

                        // Açıklama
                        InfoCard(
                            icon: "clock.fill",
                            iconColor: .blue,
                            title: "Zaman Çizelgesi",
                            descriptionText: "Belirlediğin saatte uygulama otomatik kilitlenir ve açılma saatine kadar tamamen bloke kalır.\n\nÖrnek: Gece 02:00'de kilitlenir, öğle 12:00'de otomatik açılır."
                        )

                        // Aktif et
                        HStack {
                            Text("Zaman Çizelgesini Aktif Et")
                                .font(.subheadline).foregroundColor(.white)
                            Spacer()
                            Toggle("", isOn: $config.scheduleEnabled)
                                .tint(.blue)
                        }
                        .padding(16)
                        .background(themeManager.cardBackground)
                        .cornerRadius(14)

                        // Saat seçiciler
                        VStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Kilitlenme Saati", systemImage: "lock.fill")
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(.white.opacity(0.8))
                                DatePicker("", selection: $lockTime, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.wheel)
                                    .labelsHidden()
                                    .colorScheme(.dark)
                                    .frame(maxWidth: .infinity)
                                    .disabled(!config.scheduleEnabled)
                                    .opacity(config.scheduleEnabled ? 1 : 0.3)
                            }

                            Divider().background(Color.white.opacity(0.1))

                            VStack(alignment: .leading, spacing: 10) {
                                Label("Açılma Saati", systemImage: "lock.open.fill")
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(.white.opacity(0.8))
                                DatePicker("", selection: $unlockTime, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.wheel)
                                    .labelsHidden()
                                    .colorScheme(.dark)
                                    .frame(maxWidth: .infinity)
                                    .disabled(!config.scheduleEnabled)
                                    .opacity(config.scheduleEnabled ? 1 : 0.3)
                            }
                        }
                        .padding(20)
                        .background(themeManager.cardBackground)
                        .cornerRadius(16)

                        // Özet
                        if config.scheduleEnabled {
                            let lhour = Calendar.current.component(.hour, from: lockTime)
                            let lmin  = Calendar.current.component(.minute, from: lockTime)
                            let uhour = Calendar.current.component(.hour, from: unlockTime)
                            let umin  = Calendar.current.component(.minute, from: unlockTime)
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                                Text("\(String(format: "%02d:%02d", lhour, lmin))'de kilitlenir, \(String(format: "%02d:%02d", uhour, umin))'de açılır.")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .padding(14)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                        }

                        // Kaydet
                        Button(action: {
                            let cal = Calendar.current
                            config.lockHour   = cal.component(.hour, from: lockTime)
                            config.lockMinute = cal.component(.minute, from: lockTime)
                            config.unlockHour   = cal.component(.hour, from: unlockTime)
                            config.unlockMinute = cal.component(.minute, from: unlockTime)
                            lockManager.updateLockedApp(config)
                            if config.scheduleEnabled {
                                lockManager.scheduleAutoLock(config: config)
                            } else {
                                lockManager.cancelSchedule(config: config)
                            }
                            dismiss()
                        }) {
                            Text("Kaydet")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(themeManager.accentColor)
                                .cornerRadius(16)
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle(config.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Geri")
                        }
                        .foregroundColor(themeManager.accentColor)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Gelişmiş Seçenek Satırı (NavigationLink)
struct AdvancedOptionRow<D: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let destination: D

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(iconColor.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(iconColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.25))
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Placeholder Alt Ekranlar (gerçek işlevsellik eklenebilir)
struct AutoLockTimerView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @State private var selectedMinutes = 5
    let options = [1, 2, 5, 10, 15, 30, 60]

    var body: some View {
        ZStack {
            LinearGradient(colors: themeManager.backgroundGradient, startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 20) {
                CustomSectionHeader(title: "OTOMATİK KİLİT SÜRESİ")
                    .padding(.horizontal, 18)
                ForEach(options, id: \.self) { min in
                    Button(action: { selectedMinutes = min }) {
                        HStack {
                            Text("\(min) dakika")
                                .foregroundColor(.white)
                                .padding(.horizontal, 18)
                            Spacer()
                            if selectedMinutes == min {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(themeManager.accentColor)
                                    .padding(.trailing, 18)
                            }
                        }
                        .padding(.vertical, 14)
                        .background(themeManager.cardBackground)
                        .cornerRadius(12)
                        .padding(.horizontal, 18)
                    }
                }
                Spacer()
            }
            .padding(.top, 20)
        }
        .navigationTitle("Otomatik Kilit Süresi")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NotificationSettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var notifOn = true
    @State private var vibOn = true

    var body: some View {
        ZStack {
            LinearGradient(colors: themeManager.backgroundGradient, startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Text("Kilit Bildirimleri")
                        .foregroundColor(.white)
                    Spacer()
                    Toggle("", isOn: $notifOn).tint(themeManager.accentColor)
                }
                .padding(16).background(themeManager.cardBackground).cornerRadius(14)

                HStack {
                    Text("Titreşim")
                        .foregroundColor(.white)
                    Spacer()
                    Toggle("", isOn: $vibOn).tint(themeManager.accentColor)
                }
                .padding(16).background(themeManager.cardBackground).cornerRadius(14)

                Spacer()
            }
            .padding(18)
        }
        .navigationTitle("Bildirimler")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StealthModeView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var stealthOn = false

    var body: some View {
        ZStack {
            LinearGradient(colors: themeManager.backgroundGradient, startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                InfoCard(icon: "eye.slash.fill", iconColor: .blue,
                         title: "Gizli Mod",
                         descriptionText: "Bu mod etkinleştirildiğinde AppVault, ekran süresi kısıtlamaları listesinde görünmez. Sadece hesap makinesi olarak gözükür.")
                HStack {
                    Text("Gizli Modu Etkinleştir")
                        .foregroundColor(.white)
                    Spacer()
                    Toggle("", isOn: $stealthOn).tint(.blue)
                }
                .padding(16).background(themeManager.cardBackground).cornerRadius(14)
                Spacer()
            }
            .padding(18)
        }
        .navigationTitle("Gizli Mod")
        .navigationBarTitleDisplayMode(.inline)
    }
}
