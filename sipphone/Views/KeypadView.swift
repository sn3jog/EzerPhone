import SwiftUI

struct KeypadView: View {
    @EnvironmentObject var settings: SipSettings
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var linphone = LinphoneManager.shared

    @State private var dialString: String = ""

    private var canCall: Bool { !dialString.isEmpty && settings.isConfigured }

    var body: some View {
        VStack(spacing: 0) {
            if !settings.isConfigured {
                Text("Заполните настройки SIP, чтобы начать пользоваться приложением")
                    .font(.ink(13, .italic, relativeTo: .footnote))
                    .foregroundStyle(Ink.faded)
                    .multilineTextAlignment(.center)
                    .padding()
            }

            if settings.accounts.count > 1 {
                accountPicker
                    .padding(.top, 6)
            }

            Spacer(minLength: 4)

            dialField

            DialPad(dialString: $dialString)
                .padding(.vertical, 8)

            Button {
                coordinator.placeCall(dialString, accountId: settings.selectedAccountId)
            } label: {
                InkSunburstFace(diameter: 84, glyph: .handset)
            }
            .buttonStyle(InkPressStyle())
            .disabled(!canCall)
            .accessibilityLabel("Позвонить")
            .padding(.bottom, 4)

            if let error = linphone.lastCallError {
                Text("Звонок отклонён: \(error)")
                    .font(.ink(13, .boldItalic, relativeTo: .footnote))
                    .foregroundStyle(Ink.ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer(minLength: 4)
        }
    }

    private var dialField: some View {
        VStack(spacing: 2) {
            HStack {
                // Balances the delete button so the number stays centred.
                Color.clear.frame(width: 44, height: 44)
                NoKeyboardTextField(text: $dialString, placeholder: "Номер или логин")
                    .frame(height: 40)
                if dialString.isEmpty {
                    Color.clear.frame(width: 44, height: 44)
                } else {
                    InkIconButton(glyph: .backspace, label: "Стереть") {
                        dialString.removeLast()
                    }
                }
            }
            InkRule(double: true, seed: 17)
        }
        .padding(.horizontal, 22)
        .environment(\.layoutDirection, .leftToRight)
    }

    private var accountPicker: some View {
        Menu {
            ForEach(settings.accounts) { account in
                Button {
                    settings.selectedAccountId = account.id
                } label: {
                    if account.id == settings.selectedAccountId {
                        Label(account.displayName, systemImage: "checkmark")
                    } else {
                        Text(account.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                InkGlyphView(glyph: .person, size: 16)
                Text("Звонить с: \(settings.selectedAccount?.displayName ?? "—")")
                    .font(.ink(14, .italic, relativeTo: .footnote))
                InkGlyphView(glyph: .chevronUpDown, size: 14)
            }
            .foregroundStyle(Ink.ink)
        }
        .padding(.bottom, 4)
    }
}

/// The 4x3 grid of inked keys. The dial pad and the in-call keypad both use it.
struct DialGrid: View {
    var onKey: (String) -> Void
    var onZeroLongPress: (() -> Void)? = nil

    private let rows: [[(digit: String, letters: String)]] = [
        [("1", ""), ("2", "ABC"), ("3", "DEF")],
        [("4", "GHI"), ("5", "JKL"), ("6", "MNO")],
        [("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ")],
        [("*", ""), ("0", "+"), ("#", "")]
    ]

    var body: some View {
        // A phone keypad is 1-2-3 left to right in every language.
        VStack(spacing: 8) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 10) {
                    ForEach(rows[r], id: \.digit) { key in
                        DialPadButton(
                            digit: key.digit,
                            letters: key.letters,
                            action: { onKey(key.digit) },
                            longPressAction: key.digit == "0" ? onZeroLongPress : nil
                        )
                    }
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

struct DialPad: View {
    @Binding var dialString: String

    var body: some View {
        DialGrid(onKey: appendDigit, onZeroLongPress: { dialString.append(dialString.isEmpty ? "+" : "0") })
    }

    /// "00" at the very start of a number becomes "+" (international prefix), matching the
    /// long-press shortcut. Anywhere later zeros are just zeros: "8001" must stay "8001".
    private func appendDigit(_ digit: String) {
        if digit == "0", dialString == "0" {
            dialString.removeLast()
            dialString.append("+")
        } else {
            dialString.append(digit)
        }
    }
}

struct DialPadButton: View {
    let digit: String
    let letters: String
    let action: () -> Void
    var longPressAction: (() -> Void)? = nil

    @State private var pressStart: Date?
    @State private var isPressed = false

    var body: some View {
        ZStack {
            InkDisc(diameter: 68, seed: InkSeed.of(digit), pressed: isPressed)
            VStack(spacing: 0) {
                Text(digit)
                    .font(.ink(digit == "*" ? 34 : 28, .bold, relativeTo: .title))
                    .offset(y: digit == "*" ? 5 : 0)
                Text(letters.isEmpty ? " " : letters)
                    .font(.ink(9, .italic, relativeTo: .caption2))
                    .kerning(1.5)
            }
            .foregroundStyle(isPressed ? Ink.paper : Ink.ink)
            .offset(x: isPressed ? 2 : 0, y: isPressed ? 2.4 : 0)
        }
        .frame(width: 78, height: 78)
        .contentShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(digit == "*" ? tr("Звёздочка") : digit == "#" ? tr("Решётка") : digit)
        .accessibilityAddTraits(.isButton)
        .onLongPressGesture(minimumDuration: 0.45, pressing: { pressing in
            isPressed = pressing
            if pressing {
                pressStart = Date()
                Haptics.tap()
            } else if let start = pressStart, Date().timeIntervalSince(start) < 0.45 {
                action()
            }
        }, perform: {
            Haptics.tap()
            (longPressAction ?? action)()
        })
    }
}

#Preview {
    KeypadView()
        .environmentObject(SipSettings.shared)
        .environmentObject(AppCoordinator.shared)
}
