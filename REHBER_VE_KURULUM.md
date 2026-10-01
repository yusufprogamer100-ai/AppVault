# AppVault (iOS Uygulama Gizleme & Kasa)

Bu proje tam olarak senin tarif ettiğin özelliklerle kodlanmıştır:

1. **Açılışta 4 Haneli PIN Doğrulaması:**
   - Varsayılan PIN: `0000`
   - Başarılı giriş yapılmadan ana ekrana asla geçilemez.
2. **FamilyControls & Screen Time İzinleri:**
   - Uygulama ilk açıldığında Apple'ın resmi Ekran Süresi iznini ister.
3. **Uygulama Seçimi (Add App):**
   - Apple'ın `FamilyActivityPicker` arayüzü ile TikTok veya istenen herhangi bir uygulama seçilir.
4. **Locked Apps Sekmesi & İkinci PIN Koruması:**
   - Seçilen uygulama listede görünür.
   - Ayarlarını değiştirmek için tıklandığında **tekrar PIN istenir**.
5. **Maskeleme (İsim & İkon Değiştirme):**
   - TikTok'un adını örneğin "Hesap Makinesi" veya "Notlar", ikonunu ise başka bir simge yapabilirsin.
6. **1. Kilitleme Yöntemi (Sıfır Tepki - Hiç Açılmama):**
   - `ShieldConfigurationExtension.swift` dosyası ile TikTok kilitlendiğinde Apple'ın standart uyarı metinleri, butonları kaldırılır; arkaya tamamen siyah/boş perde çekilir. Uygulamaya basıldığında hiçbir tepki vermez, açılmaz!

---

## Proje Dosya Yapısı (İndirilenler / 1 Klasöründe)

```
c:\Users\Casper\Downloads\1\
├── AppVault/
│   ├── App/
│   │   └── AppVaultApp.swift                  (Ana uygulama girişi & PIN kontrolü)
│   ├── Core/
│   │   ├── SecurityManager.swift              (PIN motoru & Şifre doğrulama)
│   │   └── LockManager.swift                  (Screen Time & Kilitleme motoru)
│   ├── Views/
│   │   ├── PasscodeView.swift                 (0000 PIN tuş takımı ekranı)
│   │   ├── MainDashboardView.swift            (Locked Apps sekmesi & Add App butonu)
│   │   └── AppCustomizerView.swift            (İsim, ikon ve kilit modu değiştirme)
│   ├── ShieldExtension/
│   │   └── ShieldConfigurationExtension.swift (Sıfır Tepki / Tepkisiz kilit kalkanı)
│   ├── AppVault.entitlements                  (Screen Time yetkilendirme dosyası)
│   └── Info.plist                             (iOS sistem izin tanımları)
├── .github/workflows/build.yml                (Ücretsiz bulut derleme motoru)
└── Package.swift
```

---

## Windows Bilgisayardan iPhone'a Nasıl Aktarılır?

### Adım 1: iPhone'da Geliştirici Modunu Aç
1. iPhone'unda **Ayarlar > Gizlilik ve Güvenlik** bölümüne git.
2. En alta inip **Geliştirici Modu (Developer Mode)** seçeneğini Aç yap.
3. Telefonu yeniden başlat ve gelen onay penceresine "Aç" de.

### Adım 2: Derleme ve IPA Alma
- Apple, **iOS SDK ve FamilyControls** kütüphanelerini sadece macOS üzerinde derlemeye izin verir.
- Bu yüzden projenin içerisine `.github/workflows/build.yml` eklendi.
- Bu klasörü ücretsiz bir **GitHub** reposuna yüklediğinde, GitHub'ın Mac sunucusu projeyi otomatik olarak derleyip sana hazır `.ipa` dosyası verir.
- (Eğer bir Mac bilgisayara erişimin varsa veya bir arkadaşının Mac'i varsa, klasörü Mac'e kopyalayıp Xcode ile açıp **Run** tuşuna basman yeterlidir).

### Adım 3: Sideloadly ile Windows'tan Yükleme
1. Windows bilgisayarına ücretsiz **[Sideloadly](https://sideloadly.io/)** programını indir ve kur.
2. iPhone'unu USB kablosu ile bilgisayara bağla ("Bu Bilgisayara Güven" uyarısına Güven de).
3. Sideloadly programını aç:
   - Cihaz kısmında iPhone'unu göreceksin.
   - Apple ID kısmına kendi normal iCloud/Apple hesabını yaz.
   - Oluşan `AppVault.ipa` dosyasını Sideloadly'nin içine sürükle.
   - **Start** butonuna bas!
4. 1 dakika içinde uygulama iPhone'unun ana ekranına yüklenecektir!
