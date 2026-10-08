import SwiftUI

struct ContactsView: View {
    @EnvironmentObject var settings: SipSettings
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var store = ContactsStore.shared

    @State private var showAdd = false
    @State private var syncMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            InkScreenHeader(title: "Контакты") {
                HStack(spacing: 0) {
                    InkIconButton(glyph: .plus, label: "Новый контакт") {
                        showAdd = true
                    }
                    if store.isSyncing {
                        ProgressView()
                            .tint(Ink.ink)
                            .frame(width: 44, height: 44)
                    } else {
                        InkIconButton(glyph: .sync, label: "Синхронизировать с телефоном") {
                            sync()
                        }
                    }
                }
            }

            if let syncMessage {
                Text(syncMessage)
                    .font(.ink(12, .italic, relativeTo: .footnote))
                    .foregroundStyle(Ink.faded)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 4)
            }

            if store.contacts.isEmpty {
                InkEmptyState(text: "Пока пусто")
                Spacer()
            } else {
                List {
                    ForEach(store.contacts) { contact in
                        ContactRow(contact: contact) {
                            coordinator.placeCall(contact.number, accountId: settings.selectedAccountId)
                        }
                        .inkRow()
                    }
                    .onDelete { store.remove(at: $0) }
                }
                .inkList()
            }
        }
        .sheet(isPresented: $showAdd) {
            AddContactView()
                .inkSheetBackground()
        }
    }

    private func sync() {
        Task {
            syncMessage = "Синхронизация…"
            let result = await store.syncFromDevice()
            switch result {
            case .success(let count):
                syncMessage = "Синхронизировано: \(count)"
            case .failure(.denied):
                syncMessage = "Нет доступа к контактам — разрешите в Настройках iOS"
            case .failure(.failed(let error)):
                syncMessage = "Ошибка: \(error.localizedDescription)"
            }
        }
    }
}

struct ContactRow: View {
    let contact: PhoneContact
    let onCall: () -> Void
    @ObservedObject private var store = ContactsStore.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                InkIconButton(
                    glyph: contact.isFavorite ? .starFilled : .star,
                    label: contact.isFavorite ? "Убрать из избранного" : "В избранное",
                    size: 22
                ) {
                    store.toggleFavorite(contact)
                }

                Button(action: onCall) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.name.isEmpty ? contact.number : contact.name)
                                .font(.ink(16, .regular, relativeTo: .body))
                                .foregroundStyle(Ink.ink)
                            if !contact.name.isEmpty {
                                Text(contact.number)
                                    .font(.ink(12, .italic, relativeTo: .caption))
                                    .foregroundStyle(Ink.faded)
                            }
                        }
                        Spacer(minLength: 8)
                        InkCallMini(size: 34)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Позвонить: \(contact.name.isEmpty ? contact.number : contact.name)")
            }
            .padding(.vertical, 3)
            InkRule(seed: InkSeed.of(contact.number + contact.name))
        }
    }
}

private struct AddContactView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var number = ""

    var body: some View {
        VStack(spacing: 0) {
            InkScreenHeader(
                title: "Новый контакт",
                leading: { InkTextButton(title: "Отмена") { dismiss() } },
                trailing: {
                    InkTextButton(title: "Сохранить", bold: true) {
                        ContactsStore.shared.add(name: name, number: number)
                        dismiss()
                    }
                    .opacity(number.isEmpty ? 0.35 : 1)
                    .disabled(number.isEmpty)
                }
            )
            .padding(.top, 10)

            ScrollView {
                InkSection {
                    InkField(title: "Имя", text: $name, capitalizes: true)
                    InkRule(seed: 31)
                    InkField(title: "Номер", text: $number, keyboard: .phonePad)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
            }
            .inkDismissesKeyboard()
        }
        .inkPaper()
    }
}

#Preview {
    ContactsView()
        .environmentObject(SipSettings.shared)
        .environmentObject(AppCoordinator.shared)
}
