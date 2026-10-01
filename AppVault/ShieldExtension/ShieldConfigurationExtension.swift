import ManagedSettings
import ManagedSettingsUI
import UIKit

// 1. YÖNTEM: SIFIR TEPKİ (HİÇ AÇILMAMA) KALKANI
// Kullanıcı kilitli uygulamaya tıkladığında Apple bu sınıfı çağırır.
// Başlık, açıklama ve butonları boş bırakarak sıfır tepki verdiriyoruz.
class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor.black,
            icon: nil, // İkon gösterme
            title: ShieldConfiguration.Label(text: "", color: .clear), // Boş başlık
            subtitle: ShieldConfiguration.Label(text: "", color: .clear), // Boş açıklama
            primaryButtonLabel: nil, // Buton yok
            secondaryButtonLabel: nil // İkincil buton yok
        )
    }
}
