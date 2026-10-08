import Foundation
import Combine
import SwiftUI
import Contacts

struct PhoneContact: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var number: String
    var isFavorite: Bool = false
    /// Set when this entry was imported from the iOS Contacts app, so a
    /// repeat sync can update it in place instead of duplicating it.
    var sourceContactId: String?
}

enum ContactsSyncError: Error {
    case denied
    case failed(Error)
}

final class ContactsStore: ObservableObject {
    static let shared = ContactsStore()

    @Published var contacts: [PhoneContact] {
        didSet { save() }
    }
    @Published private(set) var isSyncing = false

    private let key = "contacts.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([PhoneContact].self, from: data) {
            contacts = decoded
        } else {
            contacts = []
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(contacts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func add(name: String, number: String) {
        guard !number.isEmpty else { return }
        contacts.append(PhoneContact(name: name, number: number))
    }

    func remove(at offsets: IndexSet) {
        contacts.remove(atOffsets: offsets)
    }

    func remove(_ contact: PhoneContact) {
        contacts.removeAll { $0.id == contact.id }
    }

    func toggleFavorite(_ contact: PhoneContact) {
        if let idx = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[idx].isFavorite.toggle()
        }
    }

    // MARK: - Sync from the iOS Contacts app

    @discardableResult
    func syncFromDevice() async -> Result<Int, ContactsSyncError> {
        let store = CNContactStore()
        let authorized: Bool
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            authorized = true
        case .notDetermined:
            authorized = (try? await store.requestAccess(for: .contacts)) ?? false
        default:
            authorized = false
        }
        guard authorized else { return .failure(.denied) }

        await MainActor.run { isSyncing = true }
        defer { Task { @MainActor in isSyncing = false } }

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)

        var imported: [PhoneContact] = []
        do {
            try store.enumerateContacts(with: request) { cnContact, _ in
                guard let firstNumber = cnContact.phoneNumbers.first?.value.stringValue else { return }
                let name = [cnContact.givenName, cnContact.familyName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                imported.append(PhoneContact(
                    name: name,
                    number: firstNumber,
                    sourceContactId: cnContact.identifier
                ))
            }
        } catch {
            return .failure(.failed(error))
        }

        await MainActor.run {
            for synced in imported {
                if let idx = contacts.firstIndex(where: { $0.sourceContactId == synced.sourceContactId }) {
                    contacts[idx].name = synced.name
                    contacts[idx].number = synced.number
                } else {
                    contacts.append(synced)
                }
            }
        }
        return .success(imported.count)
    }
}
