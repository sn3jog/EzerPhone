import SwiftUI

struct CallView: View {
    @EnvironmentObject var linphone: LinphoneManager
    @State private var isMuted = false
    @State private var isSpeaker = false
    @State private var showKeypad = false
    @State private var sentDigits = ""

    var body: some View {
        VStack(spacing: showKeypad ? 14 : 28) {
            InkHeader()

            if showKeypad {
                keypadPanel
            } else {
                Spacer()
                callerPanel
                Spacer()
            }

            controls

            Button {
                CallKitManager.shared.endCurrentCall()
            } label: {
                InkSunburstFace(diameter: showKeypad ? 84 : 100, glyph: .handsetDown)
            }
            .buttonStyle(InkPressStyle())
            .accessibilityLabel("Завершить вызов")
            .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .inkPaper()
    }

    private var callerPanel: some View {
        VStack(spacing: 12) {
                InkAvatar(size: 150)
                Text(linphone.activeCallRemote ?? "—")
                    .font(.ink(32, .bold, relativeTo: .title))
                    .foregroundStyle(Ink.ink)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .padding(.horizontal, 24)
                HStack(spacing: 8) {
                    if !Ink.classic { Diamond().fill(Ink.ink).frame(width: 7, height: 7) }
                    Text(tr(linphone.activeCallIsIncoming ? "Входящий вызов" : "Исходящий вызов"))
                        .font(.ink(16, .italic, relativeTo: .callout))
                        .foregroundStyle(Ink.faded)
                    if !Ink.classic { Diamond().fill(Ink.ink).frame(width: 7, height: 7) }
                }
        }
    }

    /// Keypad tones for voice menus ("press 1 for…") and PINs.
    private var keypadPanel: some View {
        VStack(spacing: 6) {
            Text(linphone.activeCallRemote ?? "—")
                .font(.ink(20, .bold, relativeTo: .title3))
                .foregroundStyle(Ink.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(sentDigits.isEmpty ? " " : String(sentDigits.suffix(18)))
                .font(.ink(24, .regular, relativeTo: .title2))
                .kerning(2)
                .foregroundStyle(Ink.ink)
                .lineLimit(1)
                .frame(height: 30)
            InkRule(double: true, seed: 47)
                .padding(.horizontal, 40)
            DialGrid(onKey: { digit in
                sentDigits.append(digit)
                if let character = digit.first { linphone.sendDtmf(character) }
            })
            .padding(.top, 4)
        }
    }

    private var controls: some View {
        HStack(spacing: showKeypad ? 30 : 36) {
            CallButton(
                glyph: isMuted ? .micOff : .mic,
                label: isMuted ? "Включить микрофон" : "Выключить микрофон",
                active: isMuted
            ) {
                isMuted.toggle()
                linphone.setMuted(isMuted)
            }
            CallButton(
                glyph: .keypad,
                label: showKeypad ? "Скрыть клавиатуру" : "Показать клавиатуру",
                active: showKeypad
            ) {
                withAnimation(.easeOut(duration: 0.18)) { showKeypad.toggle() }
            }
            CallButton(
                glyph: isSpeaker ? .speakerWaves : .speaker,
                label: isSpeaker ? "Выключить громкую связь" : "Включить громкую связь",
                active: isSpeaker
            ) {
                isSpeaker.toggle()
                linphone.setSpeaker(isSpeaker)
            }
        }
    }
}

/// A drawn bust in a ring: the placeholder for "someone is on the line".
private struct InkAvatar: View {
    var size: CGFloat

    var body: some View {
        let inner = size * 0.66
        if Ink.classic {
            ZStack {
                Circle().fill(Ink.keyFill)
                InkGlyphView(glyph: .person, size: size * 0.5, color: Ink.faded)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        } else {
        ZStack {
            InkDisc(diameter: size, seed: 9, lineWidth: 3)
            ZStack {
                HatchFill(spacing: 3.2, lineWidth: 1, seed: 2)
                    .frame(width: inner * 0.95, height: inner * 0.46)
                    .mask(WobblyRoundedRect(radius: inner * 0.3, seed: 2, amplitude: 1, inset: 1.5))
                    .offset(y: inner * 0.30)
                WobblyRoundedRect(radius: inner * 0.3, seed: 2, amplitude: 1, inset: 1.5)
                    .stroke(Ink.ink, lineWidth: 2)
                    .frame(width: inner * 0.95, height: inner * 0.46)
                    .offset(y: inner * 0.30)
                WobblyCircle(seed: 3, amplitude: 1, inset: 1.5).fill(Ink.paper)
                    .frame(width: inner * 0.44, height: inner * 0.44)
                    .offset(y: -inner * 0.13)
                WobblyCircle(seed: 3, amplitude: 1, inset: 1.5).stroke(Ink.ink, lineWidth: 2)
                    .frame(width: inner * 0.44, height: inner * 0.44)
                    .offset(y: -inner * 0.13)
            }
            .frame(width: inner, height: inner)
            .clipShape(Circle())
        }
        .accessibilityHidden(true)
        }
    }
}

private struct CallButton: View {
    let glyph: InkGlyph
    let label: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                InkDisc(diameter: 64, seed: InkSeed.of(label), pressed: active)
                InkGlyphView(glyph: glyph, size: 28, color: active && !Ink.classic ? Ink.paper : Ink.ink)
                    .offset(x: active && !Ink.classic ? 2 : 0, y: active && !Ink.classic ? 2.4 : 0)
            }
            .frame(width: 72, height: 72)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr(label))
    }
}

#Preview {
    CallView()
        .environmentObject(LinphoneManager.shared)
}
