import SwiftUI

struct AppCustomizerSheet: View {
    @EnvironmentObject var lockManager: LockManager
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    @State var config: LockedAppConfig

    let camouflageIcons = [
        ("function", "Hesap Makinesi"),
        ("note.text", "Notlar"),
        ("cloud.sun.fill", "Hava Durumu"),
        ("folder.fill", "Dosyalar"),
        ("gearshape.fill", "Ayarlar"),
        ("camera.fill", "Kamera"),
        ("photo.fill", "Fotoğraflar"),
        ("calendar", "Takvim"),
        ("stopwatch.fill", "Saat"),
        ("map.fill", "Harita")
    ]

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: themeManager.backgroundGradient, startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // MARK: Önizleme
                        VStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 22)
                                    .fill(themeManager.accentColor.opacity(0.18))
                                    .frame(width: 90, height: 90)
                                Image(systemName: config.disguisedIconSystemName.isEmpty ? "app.fill" : config.disguisedIconSystemName)
                                    .font(.system(size: 40))
                                    .foregroundColor(themeManager.accentColor)
                            }
                            Text(config.disguisedName.isEmpty ? config.displayName : config.disguisedName)
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Ana Ekran Önizleme")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(20)

                        // MARK: İsim Ayarları
                        CardSection(title: "KİMLİK") {
                            CustomTextField(label: "Uygulama Adı (Gerçek)", text: $config.displayName)
                            Divider().background(Color.white.opacity(0.08))
                            CustomTextField(label: "Maskelenmiş Ad", text: $config.disguisedName, placeholder: "Hesap Makinesi")
                        }

                        // MARK: İkon Seçimi
                        CardSection(title: "MASKELEME İKONU") {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                                ForEach(camouflageIcons, id: \.0) { icon in
                                    Button(action: { config.disguisedIconSystemName = icon.0 }) {
                                        VStack(spacing: 6) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(config.disguisedIconSystemName == icon.0 ? themeManager.accentColor : Color.white.opacity(0.08))
                                                    .frame(width: 52, height: 52)
                                                Image(systemName: icon.0)
                                                    .font(.system(size: 22))
                                                    .foregroundColor(config.disguisedIconSystemName == icon.0 ? .white : .white.opacity(0.6))
                                            }
                                            Text(icon.1)
                                                .font(.system(size: 9))
                                                .foregroundColor(.white.opacity(0.5))
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        // MARK: Kilitleme Yöntemi
                        CardSection(title: "KİLİTLEME YÖNTEMİ") {
                            ForEach(LockMethod.allCases) { method in
                                Button(action: { config.lockMethod = method }) {
                                    HStack(spacing: 14) {
                                        ZStack {
                                            Circle()
                                                .fill(config.lockMethod == method ? themeManager.accentColor.opacity(0.2) : Color.white.opacity(0.06))
                                                .frame(width: 44, height: 44)
                                            Image(systemName: method.icon)
                                                .foregroundColor(config.lockMethod == method ? themeManager.accentColor : .white.opacity(0.4))
                                        }
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(method.displayName)
                                                .font(.subheadline).fontWeight(.medium)
                                                .foregroundColor(.white)
                                            Text(method.description)
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.4))
                                        }
                                        Spacer()
                                        if config.lockMethod == method {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(themeManager.accentColor)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                }
                                if method != LockMethod.allCases.last {
                                    Divider().background(Color.white.opacity(0.08))
                                }
                            }
                        }

                        // Kaydet
                        Button(action: {
                            lockManager.updateLockedApp(config)
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

                        // Sil
                        Button(action: {
                            if let idx = lockManager.lockedApps.firstIndex(where: { $0.id == config.id }) {
                                lockManager.lockedApps.remove(at: idx)
                            }
                            dismiss()
                        }) {
                            Text("Uygulamayı Listeden Kaldır")
                                .font(.subheadline)
                                .foregroundColor(.red.opacity(0.8))
                        }
                        .padding(.bottom, 20)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Uygulamayı Özelleştir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("İptal") { dismiss() }.foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
