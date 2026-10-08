import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject var settings: SipSettings
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var store = ContactsStore.shared

    private var favorites: [PhoneContact] {
        store.contacts.filter { $0.isFavorite }
    }

    var body: some View {
        VStack(spacing: 0) {
            InkScreenHeader(title: "Избранное")

            if favorites.isEmpty {
                InkEmptyState(text: "Нет избранных — отметьте звёздочкой в Контактах")
                Spacer()
            } else {
                List {
                    ForEach(favorites) { contact in
                        ContactRow(contact: contact) {
                            coordinator.placeCall(contact.number, accountId: settings.selectedAccountId)
                        }
                        .inkRow()
                    }
                }
                .inkList()
            }
        }
    }
}

#Preview {
    FavoritesView()
        .environmentObject(SipSettings.shared)
        .environmentObject(AppCoordinator.shared)
}
