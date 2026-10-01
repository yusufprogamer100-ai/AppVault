import SwiftUI

struct CalculatorView: View {
    @EnvironmentObject var securityManager: SecurityManager
    @EnvironmentObject var themeManager: ThemeManager

    @State private var display: String = "0"
    @State private var currentInput: String = ""
    @State private var shakeOffset: CGFloat = 0

    // Gerçek hesap makinesi tuşları
    let buttons: [[CalcButton]] = [
        [.ac, .plusMinus, .percent, .divide],
        [.seven, .eight, .nine, .multiply],
        [.four, .five, .six, .minus],
        [.one, .two, .three, .plus],
        [.zero, .decimal, .equals]
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Ekran
                HStack {
                    Spacer()
                    Text(display)
                        .font(.system(size: display.count > 9 ? 52 : 72, weight: .thin, design: .default))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(.horizontal, 28)
                        .offset(x: shakeOffset)
                }
                .padding(.bottom, 12)

                // Tuş Takımı
                VStack(spacing: 14) {
                    ForEach(buttons, id: \.self) { row in
                        HStack(spacing: 14) {
                            ForEach(row, id: \.self) { btn in
                                CalcButtonView(button: btn, action: {
                                    handleButton(btn)
                                }, longPressAction: btn == .zero ? {
                                    withAnimation(.spring()) {
                                        securityManager.isUnlocked = true
                                    }
                                } : nil)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: Hesap Makinesi Mantığı
    private func handleButton(_ btn: CalcButton) {
        switch btn {
        case .ac:
            display = "0"
            currentInput = ""

        case .plusMinus:
            if let val = Double(currentInput), val != 0 {
                currentInput = String(-val)
                display = formatDisplay(currentInput)
            }

        case .percent:
            if let val = Double(currentInput) {
                currentInput = String(val / 100)
                display = formatDisplay(currentInput)
            }

        case .equals:
            // Normal hesaplama (basit gösterim)
            display = currentInput.isEmpty ? "0" : formatDisplay(currentInput)
            currentInput = ""

        case .divide, .multiply, .minus, .plus:
            // Operatör tuşları
            if !currentInput.isEmpty {
                display = formatDisplay(currentInput)
            }
            currentInput = currentInput + btn.rawValue

        case .decimal:
            if !currentInput.contains(".") {
                currentInput += currentInput.isEmpty ? "0." : "."
                display = currentInput
            }

        default:
            let digit = btn.rawValue
            if currentInput == "0" {
                currentInput = digit
            } else {
                currentInput += digit
            }
            display = formatDisplay(currentInput)
        }
    }

    private func formatDisplay(_ text: String) -> String {
        // Sadece sayısal kısmı göster
        let cleanText = text.components(separatedBy: CharacterSet(charactersIn: "+-×÷")).last ?? text
        if let val = Double(cleanText) {
            if val == val.rounded() && !cleanText.contains(".") {
                return String(format: "%.0f", val)
            }
        }
        return cleanText.isEmpty ? "0" : cleanText
    }

    private func shake() {
        withAnimation(.default) { shakeOffset = 10 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.default) { shakeOffset = -10 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.default) { shakeOffset = 0 }
            }
        }
    }
}

// MARK: Hesap Makinesi Tuş Tipleri
enum CalcButton: String, CaseIterable, Hashable {
    case zero = "0", one = "1", two = "2", three = "3", four = "4"
    case five = "5", six = "6", seven = "7", eight = "8", nine = "9"
    case decimal = ".", equals = "=", plus = "+", minus = "-"
    case multiply = "×", divide = "÷", ac = "AC", plusMinus = "+/-", percent = "%"

    var displayTitle: String { self.rawValue }

    var backgroundColor: Color {
        switch self {
        case .ac, .plusMinus, .percent:
            return Color(white: 0.6)
        case .divide, .multiply, .minus, .plus, .equals:
            return Color.orange
        default:
            return Color(white: 0.2)
        }
    }

    var foregroundColor: Color {
        switch self {
        case .ac, .plusMinus, .percent:
            return .black
        default:
            return .white
        }
    }

    var isWide: Bool { self == .zero }
}

// MARK: Hesap Makinesi Tuş Görünümü
struct CalcButtonView: View {
    let button: CalcButton
    let action: () -> Void
    var longPressAction: (() -> Void)? = nil

    @State private var isPressed = false
    private let buttonSize: CGFloat = (UIScreen.main.bounds.width - 5 * 14) / 4

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: buttonSize / 2)
                .fill(button.backgroundColor)
                .frame(
                    width: button.isWide ? buttonSize * 2 + 14 : buttonSize,
                    height: buttonSize
                )
            Text(button.displayTitle)
                .font(.system(size: 32, weight: .regular))
                .foregroundColor(button.foregroundColor)
                .frame(
                    maxWidth: .infinity,
                    alignment: button.isWide ? .leading : .center
                )
                .padding(.leading, button.isWide ? 36 : 0)
        }
        .opacity(isPressed ? 0.6 : 1.0)
        .frame(
            width: button.isWide ? buttonSize * 2 + 14 : buttonSize,
            height: buttonSize
        )
        .onTapGesture {
            action()
        }
        .onLongPressGesture(minimumDuration: 0.8) {
            if let longAction = longPressAction {
                longAction()
            } else {
                action()
            }
        } onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }
    }
}
