import SwiftUI

private struct EditingAccountRef: Identifiable {
    let id: UUID
}

struct SettingsView: View {
    @EnvironmentObject var settings: SipSettings
    @EnvironmentObject var linphone: LinphoneManager
    @EnvironmentObject var coordinator: AppCoordinator

    @State private var editingAccount: EditingAccountRef?
    @State private var pendingDelete: EditingAccountRef?
    @State private var isReordering = false

    var body: some View {
        VStack(spacing: 0) {
            InkScreenHeader(title: "Настройки") {
                InkTextButton(title: isReordering ? "Готово" : "Изменить") {
                    withAnimation(.easeOut(duration: 0.15)) { isReordering.toggle() }
                }
            }

            ScrollView {
                VStack(spacing: 18) {
                    InkSection("SIP-аккаунты", footer: footerText) {
                        // Rows are keyed and edited by account id, never by index or by
                        // element bindings: those can point at the wrong account after a move.
                        ForEach(settings.accounts) { account in
                            accountRow(account)
                            InkRule(seed: InkSeed.of(account.id.uuidString))
                        }
                        addButton
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .inkBouncesOnlyWhenNeeded()
        }
        .inkOnChange(of: settings.accounts) { _ in
            coordinator.settingsDidChange()
        }
        // .sheet(item:) with an Identifiable wrapper — not isPresented plus a captured
        // index, which produced a blank sheet when registration state changed underneath.
        .sheet(item: $editingAccount) { ref in
            if let idx = settings.accounts.firstIndex(where: { $0.id == ref.id }) {
                AccountEditView(account: $settings.accounts[idx]) {
                    editingAccount = nil
                    coordinator.settingsDidChange()
                }
                .inkSheetBackground()
            } else {
                Text("Аккаунт удалён")
                    .font(.ink(16, .italic))
                    .inkSheetBackground()
            }
        }
        .confirmationDialog(
            "Удалить аккаунт?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let id = pendingDelete?.id { delete(id) }
                pendingDelete = nil
            }
            Button("Отмена", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Вместе с ним будут удалены сохранённые пароли.")
        }
    }

    private var footerText: String {
        "Верхний аккаунт — по умолчанию для звонков; нажмите на значок слева, чтобы сделать аккаунт основным, "
        + "стрелки рядом переставляют аккаунты, а «Изменить» открывает удаление. Закрашенный значок — зарегистрирован, "
        + "штриховка — идёт регистрация, крест — ошибка, пустой — неактивен; двойное кольцо — аккаунт по умолчанию. "
        + "Переключатель справа включает и выключает аккаунт. Доступ (стук) и VPN настраиваются внутри аккаунта."
    }

    private func enabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { settings.accounts.first(where: { $0.id == id })?.enabled ?? false },
            set: { newValue in
                if let i = settings.accounts.firstIndex(where: { $0.id == id }) {
                    settings.accounts[i].enabled = newValue
                }
            })
    }

    private func accountRow(_ value: SipAccount) -> some View {
        let index = settings.accounts.firstIndex(where: { $0.id == value.id }) ?? 0
        return HStack(spacing: 12) {
            Button {
                makeDefault(value.id)
            } label: {
                InkStatusMark(kind: statusKind(value.id), size: 28, isDefault: value.id == settings.selectedAccountId)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Сделать основным: \(value.displayName)")

            Button {
                editingAccount = EditingAccountRef(id: value.id)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(value.displayName)
                        .font(.ink(17, .bold, relativeTo: .headline))
                        .foregroundStyle(Ink.ink)
                    Text("\(value.username)@\(value.domain)")
                        .font(.ink(12, .italic, relativeTo: .caption))
                        .foregroundStyle(Ink.faded)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(spacing: 0) {
                InkIconButton(glyph: .chevronUp, label: "Выше: \(value.displayName)", size: 20) { move(index, by: -1) }
                    .frame(width: 40, height: 28)
                    .opacity(index == 0 ? 0.25 : 1)
                    .disabled(index == 0)
                InkIconButton(glyph: .chevronDown, label: "Ниже: \(value.displayName)", size: 20) { move(index, by: 1) }
                    .frame(width: 40, height: 28)
                    .opacity(index == settings.accounts.count - 1 ? 0.25 : 1)
                    .disabled(index == settings.accounts.count - 1)
            }

            if isReordering {
                InkIconButton(glyph: .trash, label: "Удалить", size: 22) {
                    pendingDelete = EditingAccountRef(id: value.id)
                }
            } else {
                InkSwitchButton(isOn: enabledBinding(value.id), label: "Включить \(value.displayName)")
            }
        }
        .padding(.vertical, 4)
    }

    private var addButton: some View {
        InkWideButton(title: "Добавить аккаунт", glyph: .plus) {
            let newAccount = SipAccount(label: "", domain: "", port: 5061, username: "", transportIsTLS: true)
            settings.accounts.append(newAccount)
            editingAccount = EditingAccountRef(id: newAccount.id)
        }
        .padding(.vertical, 10)
    }

    private func statusKind(_ accountId: UUID) -> InkStatusMark.Kind {
        switch linphone.registrationStates[accountId] {
        case .ok: return .registered
        case .progress: return .progress
        case .failed: return .failed
        default: return .inactive
        }
    }

    private func makeDefault(_ accountId: UUID) {
        if let idx = settings.accounts.firstIndex(where: { $0.id == accountId }), idx != 0 {
            let account = settings.accounts.remove(at: idx)
            settings.accounts.insert(account, at: 0)
        }
        settings.selectedAccountId = accountId
    }

    /// Moving an account to the top makes it the default for calls.
    private func move(_ index: Int, by delta: Int) {
        let target = index + delta
        var list = settings.accounts
        guard list.indices.contains(index), list.indices.contains(target) else { return }
        list.swapAt(index, target)
        withAnimation(.easeOut(duration: 0.18)) {
            settings.accounts = list
        }
        settings.selectedAccountId = list.first?.id
        Haptics.tap()
    }

    private func delete(_ id: UUID) {
        settings.removeAllSecrets(for: id)
        settings.accounts.removeAll { $0.id == id }
    }
}

private struct AccountEditView: View {
    @Binding var account: SipAccount
    var onDone: () -> Void
    @EnvironmentObject var settings: SipSettings

    @State private var password: String = ""
    @State private var portText: String = ""
    @State private var knockIntervalText: String = ""
    @State private var knockToken: String = ""
    @State private var vpnPassword: String = ""
    @State private var vpnSharedSecret: String = ""

    var body: some View {
        VStack(spacing: 0) {
            InkScreenHeader(title: account.label.isEmpty ? "Новый аккаунт" : account.label) {
                InkTextButton(title: "Готово", bold: true, action: onDone)
            }
            .padding(.top, 10)

            ScrollView {
                VStack(spacing: 18) {
                    InkSection("SIP-сервер") {
                        InkField(title: "Название (например Работа)", text: $account.label, capitalizes: true)
                        InkRule(seed: 21)
                        InkField(title: "Домен или IP", text: $account.domain)
                        InkRule(seed: 22)
                        InkField(title: "Порт", text: $portText, keyboard: .numberPad)
                            .inkOnChange(of: portText) { newValue in
                                account.port = Int(newValue) ?? account.port
                            }
                        InkRule(seed: 23)
                        InkToggleRow(title: "TLS-транспорт", isOn: $account.transportIsTLS)
                        InkRule(seed: 24)
                        InkToggleRow(title: "Шифровать звук (SRTP)", isOn: $account.requireSRTP)
                        InkRule(seed: 25)
                        InkField(title: "Внутренний номер (логин)", text: $account.username)
                        InkRule(seed: 26)
                        InkField(title: "Пароль", text: $password, secure: true)
                    }

                    InkSection(
                        "Доступ",
                        footer: "Если сервер этого аккаунта закрыт по IP-списку (как WebFig на MikroTik), укажите HTTPS-адрес, который добавляет текущий IP в список перед подключением."
                    ) {
                        InkToggleRow(title: "Стучать перед регистрацией", isOn: $account.knockEnabled)
                        if account.knockEnabled {
                            InkRule(seed: 27)
                            InkField(title: "Knock URL", text: $account.knockURL, keyboard: .URL)
                            InkRule(seed: 28)
                            InkField(title: "Токен (если нужен)", text: $knockToken, secure: true)
                            InkRule(seed: 29)
                            InkField(title: "Перестук каждые N минут", text: $knockIntervalText, keyboard: .numberPad)
                                .inkOnChange(of: knockIntervalText) { newValue in
                                    account.knockIntervalMinutes = Int(newValue) ?? account.knockIntervalMinutes
                                }
                        }
                    }

                    InkSection(
                        "VPN",
                        footer: "Недоступно: Personal VPN capability не поддерживается бесплатным Apple ID (Personal Team) — нужен платный Developer Program, так же как для фоновых звонков (PushKit)."
                    ) {
                        InkToggleRow(title: "Подключать VPN перед регистрацией", isOn: .constant(false), disabled: true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
            .inkDismissesKeyboard()
        }
        .inkPaper()
        .onAppear {
            portText = String(account.port)
            knockIntervalText = String(account.knockIntervalMinutes)
            password = settings.password(for: account.id)
            knockToken = settings.knockToken(for: account.id)
            vpnPassword = settings.vpnPassword(for: account.id)
            vpnSharedSecret = settings.vpnSharedSecret(for: account.id)
        }
        .inkOnChange(of: password) { newValue in
            settings.setPassword(newValue, for: account.id)
        }
        .inkOnChange(of: knockToken) { newValue in
            settings.setKnockToken(newValue, for: account.id)
        }
        .inkOnChange(of: vpnPassword) { newValue in
            settings.setVpnPassword(newValue, for: account.id)
        }
        .inkOnChange(of: vpnSharedSecret) { newValue in
            settings.setVpnSharedSecret(newValue, for: account.id)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SipSettings.shared)
        .environmentObject(LinphoneManager.shared)
        .environmentObject(AppCoordinator.shared)
}
