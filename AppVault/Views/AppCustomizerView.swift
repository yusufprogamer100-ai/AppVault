import SwiftUI

struct AppCustomizerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var lockManager = LockManager.shared
    
    // Varsayılan / Seçilen Uygulama Bilgileri
    @State var appTitle: String = "TikTok"
    @State var disguisedTitle: String = "Hesap Makinesi"
    @State var selectedIconName: String = "function"
    @State var selectedMethod: LockMethod = .zeroResponse
    
    // Örnek Kamufle İkon Seçenekleri
    let camouflageIcons = [
        ("function", "Hesap Makinesi"),
        ("note.text", "Notlar"),
        ("weather.sun", "Hava Durumu"),
        ("folder.fill", "Dosyalar"),
        ("gearshape.fill", "Ayarlar")
    ]
    
    var body: some View {
        Form {
            Section(header: Text("Orijinal Uygulama")) {
                HStack {
                    Image(systemName: "app.badge.fill")
                        .foregroundColor(.blue)
                        .font(.title2)
                    Text(appTitle)
                        .fontWeight(.semibold)
                }
            }
            
            Section(header: Text("Maskeleme / Kamuflaj (İsim & Görünüm)")) {
                TextField("Sahte Uygulama Adı", text: $disguisedTitle)
                
                Picker("Sahte İkon Seç", selection: $selectedIconName) {
                    ForEach(camouflageIcons, id: \.0) { icon in
                        HStack {
                            Image(systemName: icon.0)
                            Text(icon.1)
                        }.tag(icon.0)
                    }
                }
            }
            
            Section(header: Text("Kilitleme Metodu")) {
                Picker("Metot", selection: $selectedMethod) {
                    ForEach(LockMethod.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.inline)
                
                if selectedMethod == .zeroResponse {
                    Text("ℹ️ Uygulama ikonuna basıldığında hiçbir tepki verilmez, açılmaz ve boş/karanlık perde ile sistem tarafından engellenir.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("ℹ️ Sahte Çökme: Uygulama açılır gibi yapıp anında sahte bir hata verir ve ana ekrana geri atar.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section {
                Button(action: saveChanges) {
                    HStack {
                        Spacer()
                        Text("Ayarları Kaydet")
                            .bold()
                            .foregroundColor(.white)
                        Spacer()
                    }
                }
                .listRowBackground(Color.blue)
            }
        }
        .navigationTitle("Uygulamayı Özelleştir")
    }
    
    private func saveChanges() {
        let customization = AppCustomization(
            id: appTitle,
            originalName: appTitle,
            disguisedName: disguisedTitle,
            disguisedIconName: selectedIconName,
            lockMethod: selectedMethod.rawValue
        )
        lockManager.customConfigurations[appTitle] = customization
        dismiss()
    }
}
