import SwiftUI

struct PasscodeView: View {
    @EnvironmentObject var securityManager: SecurityManager
    @EnvironmentObject var themeManager: ThemeManager

    var title: String = "AppVault"
    var subtitle: String = "PIN kodunu gir"
    var onUnlockSuccess: () -> Void

    @State private var pin: String = ""
    @State private var shakeOffset: CGFloat = 0
    @State private var showError = false

    let buttons = [
        ["1","2","3"],
        ["4","5","6"],
        ["7","8","9"],
        ["","0","⌫"]
    ]

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // İkon
            ZStack {
                Circle()
                    .fill(themeManager.accentColor.opacity(0.15))
                    .frame(width: 90, height: 90)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 40))
                    .foregroundColor(themeManager.accentColor)
            }

            // Başlık
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.5))
            }

            // PIN Noktaları
            HStack(spacing: 18) {
                ForEach(0..<4) { i in
                    Circle()
                        .fill(i < pin.count ? themeManager.accentColor : Color.white.opacity(0.2))
                        .frame(width: 16, height: 16)
                        .animation(.spring(duration: 0.2), value: pin.count)
                }
            }
            .offset(x: shakeOffset)

            if showError {
                Text("Hatalı PIN")
                    .font(.caption)
                    .foregroundColor(.red)
                    .transition(.opacity)
            }

            Spacer()

            // Tuş Takımı
            VStack(spacing: 16) {
                ForEach(buttons, id: \.self) { row in
                    HStack(spacing: 24) {
                        ForEach(row, id: \.self) { key in
                            if key.isEmpty {
                                Circle()
                                    .fill(Color.clear)
                                    .frame(width: 78, height: 78)
                            } else {
                                Button(action: { handleKey(key) }) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.white.opacity(key == "⌫" ? 0 : 0.1))
                                            .frame(width: 78, height: 78)
                                        if key == "⌫" {
                                            Image(systemName: "delete.left.fill")
                                                .font(.system(size: 22))
                                                .foregroundColor(.white.opacity(0.6))
                                        } else {
                                            Text(key)
                                                .font(.system(size: 30, weight: .light))
                                                .foregroundColor(.white)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 40)
        }
    }

    private func handleKey(_ key: String) {
        if key == "⌫" {
            if !pin.isEmpty { pin.removeLast() }
            showError = false
        } else if pin.count < 4 {
            pin.append(key)
            if pin.count == 4 {
                checkPin()
            }
        }
    }

    private func checkPin() {
        if securityManager.verifyPin(pin) {
            pin = ""
            showError = false
            onUnlockSuccess()
        } else {
            withAnimation(.spring()) { shakeOffset = 12 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring()) { shakeOffset = -12 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring()) { shakeOffset = 0 }
                }
            }
            showError = true
            pin = ""
        }
    }
}
