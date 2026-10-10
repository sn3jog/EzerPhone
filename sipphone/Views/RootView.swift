import SwiftUI

struct RootView: View {
    @EnvironmentObject var settings: SipSettings
    @EnvironmentObject var linphone: LinphoneManager
    @ObservedObject private var provisioning = ProvisioningService.shared
    @ObservedObject private var language = AppLanguage.shared

    private enum Tab: Hashable {
        case favorites, recents, contacts, keypad, settings
    }

    @State private var selectedTab: Tab = .keypad

    var body: some View {
        VStack(spacing: 0) {
            InkHeader()
            InkStatusRow(kind: statusKind, text: statusText)

            Group {
                switch selectedTab {
                case .favorites: FavoritesView()
                case .recents: RecentsView()
                case .contacts: ContactsView()
                case .keypad: KeypadView()
                case .settings: SettingsView()
                }
            }
            .id(language.choice)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            customTabBar
        }
        .environment(\.locale, language.locale)
        .environment(\.layoutDirection, language.layoutDirection)
        .inkPaper()
        .fullScreenCover(isPresented: Binding(
            get: { linphone.activeCallRemote != nil },
            set: { _ in }
        )) {
            CallView()
        }
        .sheet(isPresented: Binding(
            get: { provisioning.state != .idle },
            set: { if !$0 { provisioning.state = .idle } }
        )) {
            ProvisioningSheet(service: provisioning)
                .inkSheetBackground()
        }
    }

    // The native tab bar can't be drawn by hand (and iOS 26's glass version ignores
    // solid backgrounds anyway), so this one is built from scratch.
    private var customTabBar: some View {
        VStack(spacing: 0) {
            InkRule(double: true, seed: 9)
                .padding(.horizontal, 14)
            HStack(spacing: 0) {
                tabButton(.favorites, glyph: .star, label: "Избранное")
                tabButton(.recents, glyph: .clock, label: "История")
                tabButton(.contacts, glyph: .person, label: "Контакты")
                tabButton(.keypad, glyph: .keypad, label: "Клавиатура")
                settingsTabButton
            }
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
        .background(Ink.paper.ignoresSafeArea(edges: .bottom))
    }

    private func tabButton(_ tab: Tab, glyph: InkGlyph, label: String) -> some View {
        tabItem(tab, label: label) {
            InkGlyphView(glyph: glyph, size: 24)
        }
    }

    // The gear keeps its own drawing (with the faint hexagram between its teeth).
    private var settingsTabButton: some View {
        tabItem(.settings, label: "Настройки") {
            Image(uiImage: GearIconFactory.makeIcon(size: 26))
                .renderingMode(.template)
        }
    }

    private func tabItem<Icon: View>(_ tab: Tab, label: String, @ViewBuilder icon: () -> Icon) -> some View {
        let selected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    if selected {
                        WobblyCircle(seed: 61, amplitude: 0.6, inset: 2).stroke(Ink.ink, lineWidth: 1.8)
                        WobblyCircle(seed: 62, amplitude: 0.5, inset: 5.4).stroke(Ink.ink, lineWidth: 0.8)
                    }
                    icon()
                }
                .frame(width: 40, height: 40)
                Text(tr(label))
                    .font(.ink(10.5, selected ? .bold : .regular, relativeTo: .caption2))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Ink.ink.opacity(selected ? 1 : 0.6))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr(label))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var statusKind: InkStatusMark.Kind {
        switch linphone.registrationState {
        case .ok: return .registered
        case .progress: return .progress
        case .failed: return .failed
        default: return .inactive
        }
    }

    private var statusText: String {
        switch linphone.registrationState {
        case .ok: return tr("Зарегистрирован")
        case .progress: return tr("Регистрация…")
        case .failed: return tr("Ошибка: %@", linphone.registrationError ?? "")
        case .cleared: return tr("Отключено")
        case .none: return tr("Не настроено")
        }
    }
}

#Preview {
    RootView()
        .environmentObject(SipSettings.shared)
        .environmentObject(LinphoneManager.shared)
        .environmentObject(AppCoordinator.shared)
}
