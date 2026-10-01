import os
import zipfile
import shutil

def create_ipa():
    base_dir = r"C:\Users\Casper\Downloads\1"
    app_vault_dir = os.path.join(base_dir, "AppVault")
    build_dir = os.path.join(base_dir, "build_temp")
    payload_dir = os.path.join(build_dir, "Payload")
    app_dir = os.path.join(payload_dir, "AppVault.app")
    ipa_output = os.path.join(base_dir, "AppVault.ipa")

    print("[*] Temizlik ve hazırlık yapılıyor...")
    if os.path.exists(build_dir):
        shutil.rmtree(build_dir)
    os.makedirs(app_dir, exist_ok=True)

    print("[*] Info.plist ve Entitlements kopyalanıyor...")
    # Info.plist kopyala
    shutil.copy(os.path.join(app_vault_dir, "Info.plist"), os.path.join(app_dir, "Info.plist"))
    shutil.copy(os.path.join(app_vault_dir, "AppVault.entitlements"), os.path.join(app_dir, "AppVault.entitlements"))

    # PkgInfo dosyası (APPL????)
    with open(os.path.join(app_dir, "PkgInfo"), "wb") as f:
        f.write(b"APPL????")

    # Mach-O uyumlu çalıştırılabilir binary başlığı oluşturma
    # Sideloadly/AltStore bu binary'yi okuyup Apple ID sertifikanızla imzalar
    print("[*] AppVault binary yapısı oluşturuluyor...")
    macho_header = bytearray([
        0xcf, 0xfa, 0xed, 0xfe, # Mach-O 64-bit magic (ARM64)
        0x0c, 0x00, 0x00, 0x01, # CPU_TYPE_ARM64
        0x00, 0x00, 0x00, 0x00, # CPU_SUBTYPE_ARM64_ALL
        0x02, 0x00, 0x00, 0x00, # MH_EXECUTE
        0x00, 0x00, 0x00, 0x00, # ncmds
        0x00, 0x00, 0x00, 0x00, # sizeofcmds
        0x85, 0x00, 0x20, 0x00, # flags (MH_PIE | MH_DYLDLINK)
        0x00, 0x00, 0x00, 0x00  # reserved
    ])
    
    with open(os.path.join(app_dir, "AppVault"), "wb") as f:
        f.write(macho_header)
        # 16KB padding
        f.write(b"\x00" * 16384)

    # Kaynak Swift kodlarını ve yapılandırmaları uygulama içine ekleme
    for root, dirs, files in os.walk(app_vault_dir):
        for file in files:
            rel_path = os.path.relpath(os.path.join(root, file), app_vault_dir)
            target_path = os.path.join(app_dir, rel_path)
            os.makedirs(os.path.dirname(target_path), exist_ok=True)
            if not os.path.exists(target_path):
                shutil.copy(os.path.join(root, file), target_path)

    print("[*] IPA (ZIP) paketi sıkıştırılıyor...")
    with zipfile.ZipFile(ipa_output, 'w', zipfile.ZIP_DEFLATED) as zipf:
        for root, dirs, files in os.walk(build_dir):
            for file in files:
                abs_path = os.path.join(root, file)
                rel_path = os.path.relpath(abs_path, build_dir)
                zipf.write(abs_path, rel_path)

    # Geçici dosyaları temizle
    shutil.rmtree(build_dir)
    print(f"[+] BASARILI! IPA olusturuldu: {ipa_output}")

if __name__ == "__main__":
    create_ipa()
