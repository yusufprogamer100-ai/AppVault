import SwiftUI
import FamilyControls

struct MainDashboardView: View {
    @ObservedObject var lockManager = LockManager.shared
    @ObservedObject var securityManager = SecurityManager.shared
    
    @State private var isPickerPresented: Bool = false
    @State private var showPinSheet: Bool = false
    @State private var showCustomizer: Bool = false
    @State private var selectedAppToEdit: String = "TikTok"
    
    var body: some View {
        NavigationView {
            VStack {
                // İzin Uyarısı (Eğer FamilyControls onayı henüz yoksa)
                if !lockManager.isAuthorized {
                    VStack(spacing: 8) {
                        Text("Screen Time / Aile Denetimleri İzni Gerekiyor")
                            .font(.headline)
                            .foregroundColor(.orange)
                        Button("İzin Ver (Screen Time)") {
                            Task {
                                await lockManager.requestAuthorization()
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
                // Kilitli Uygulamalar Listesi
                List {
                    Section(header: Text("Kilitli Uygulamalar (Locked Apps)")) {
                        // Örnek Korumalı Uygulama Kartı (TikTok)
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("TikTok")
                                    .font(.headline)
                                Text("Görünüm: \(lockManager.customConfigurations["TikTok"]?.disguisedName ?? "Orijinal")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                // Özelleştirmek için PIN doğrulaması iste
                                showPinSheet = true
                            }) {
                                Image(systemName: "slider.horizontal.3")
                                    .foregroundColor(.blue)
                                    .padding(8)
                            }
                        }
                    }
                    
                    Section(header: Text("Kilit Durumu")) {
                        Toggle(isOn: Binding(
                            get: { lockManager.isShieldActive },
                            set: { newValue in
                                if newValue {
                                    lockManager.lockApplications()
                                } else {
                                    lockManager.unlockApplications()
                                }
                            }
                        )) {
                            Text(lockManager.isShieldActive ? "Uygulamalar Kilitli (Shield Aktif)" : "Kilitler Açık")
                                .fontWeight(.semibold)
                                .foregroundColor(lockManager.isShieldActive ? .red : .primary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                
                // Add App Butonu
                Button(action: {
                    isPickerPresented = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add App (Uygulama Ekle / Seç)")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .padding()
                .familyActivityPicker(isPresented: $isPickerPresented, selection: $lockManager.activitySelection)
            }
            .navigationTitle("Locked Apps")
            .sheet(isPresented: $showPinSheet) {
                // Özelleştirmeden önce tekrar PIN soran ara ekran
                PasscodeView(title: "Güvenlik Doğrulaması", subtitle: "TikTok ayarlarını değiştirmek için PIN girin") {
                    showPinSheet = false
                    showCustomizer = true
                }
            }
            .sheet(isPresented: $showCustomizer) {
                NavigationView {
                    AppCustomizerView(appTitle: selectedAppToEdit)
                }
            }
        }
    }
}
