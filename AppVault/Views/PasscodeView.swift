import SwiftUI

struct PasscodeView: View {
    @ObservedObject var securityManager = SecurityManager.shared
    
    var title: String = "Güvenli Kasa"
    var subtitle: String = "4 Haneli PIN Kodunu Girin"
    var onUnlockSuccess: () -> Void
    
    @State private var inputPin: String = ""
    @State private var showError: Bool = false
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text(title)
                    .font(.title)
                    .fontWeight(.bold)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // PIN Göstergesi
                HStack(spacing: 20) {
                    ForEach(0..<4) { index in
                        Circle()
                            .fill(index < inputPin.count ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 18, height: 18)
                    }
                }
                .padding(.vertical, 10)
                
                if showError {
                    Text("Hatalı PIN! Lütfen tekrar deneyin.")
                        .foregroundColor(.red)
                        .font(.caption)
                        .transition(.opacity)
                }
                
                Spacer()
                
                // Tuş Takımı
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 25) {
                    ForEach(1...9, id: \.self) { num in
                        KeypadCircleButton(label: "\(num)") {
                            appendDigit("\(num)")
                        }
                    }
                    
                    KeypadCircleButton(label: "Sil", isSystem: true) {
                        if !inputPin.isEmpty {
                            inputPin.removeLast()
                            showError = false
                        }
                    }
                    
                    KeypadCircleButton(label: "0") {
                        appendDigit("0")
                    }
                    
                    KeypadCircleButton(label: "OK", isSystem: true) {
                        checkPin()
                    }
                }
                .padding(.horizontal, 40)
                
                Spacer()
            }
        }
    }
    
    private func appendDigit(_ digit: String) {
        if inputPin.count < 4 {
            inputPin.append(digit)
            if inputPin.count == 4 {
                checkPin()
            }
        }
    }
    
    private func checkPin() {
        if securityManager.verifyPin(inputPin) {
            showError = false
            onUnlockSuccess()
        } else {
            showError = true
            inputPin = ""
        }
    }
}

struct KeypadCircleButton: View {
    let label: String
    var isSystem: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(isSystem ? .headline : .title)
                .foregroundColor(.primary)
                .frame(width: 75, height: 75)
                .background(Color(UIColor.secondarySystemFill))
                .clipShape(Circle())
        }
    }
}
