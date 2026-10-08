import Foundation
import Combine

/// Persisted SIP accounts, each with its own access (knock) and VPN config.
final class SipSettings: ObservableObject {
    static let shared = SipSettings()

    private let defaults = UserDefaults.standard

    @Published var accounts: [SipAccount] {
        didSet { saveAccounts() }
    }
    @Published var selectedAccountId: UUID? {
        didSet { defaults.set(selectedAccountId?.uuidString, forKey: Keys.selectedAccountId) }
    }

    private enum Keys {
        static let accounts = "sip.accounts.v3"
        static let selectedAccountId = "sip.selectedAccountId"
        // v2: accounts existed but knock/VPN were still global.
        static let legacyAccountsV2 = "sip.accounts.v2"
        static let legacyKnockEnabled = "access.knockEnabled"
        static let legacyKnockURL = "access.knockURL"
        static let legacyKnockToken = "access.knockToken"
        static let legacyKnockInterval = "access.knockIntervalMinutes"
        static let legacyVpnServer = "vpn.server"
        static let legacyVpnUsername = "vpn.username"
        // v1: a single hardcoded account, no array at all.
        static let legacyDomain = "sip.domain"
        static let legacyPort = "sip.port"
        static let legacyUsername = "sip.username"
        static let legacyPassword = "sip.password"
        static let legacyTransport = "sip.transportIsTLS"
    }

    private init() {
        if let data = defaults.data(forKey: Keys.accounts),
           let decoded = try? JSONDecoder().decode([SipAccount].self, from: data) {
            accounts = decoded
        } else {
            accounts = []
        }
        selectedAccountId = defaults.string(forKey: Keys.selectedAccountId).flatMap(UUID.init)

        if accounts.isEmpty {
            migrateFromV2IfNeeded()
        }
        if accounts.isEmpty {
            migrateFromV1IfNeeded()
        }
    }

    /// v2 accounts existed already but with global knock/VPN settings —
    /// carry those into every migrated account since they used to apply to
    /// all of them anyway.
    private func migrateFromV2IfNeeded() {
        guard let data = defaults.data(forKey: Keys.legacyAccountsV2),
              let decoded = try? JSONDecoder().decode([SipAccount].self, from: data),
              !decoded.isEmpty else { return }

        let knockEnabled = defaults.object(forKey: Keys.legacyKnockEnabled) as? Bool ?? false
        let knockURL = defaults.string(forKey: Keys.legacyKnockURL) ?? ""
        let knockToken = KeychainStore.get(forKey: Keys.legacyKnockToken) ?? ""
        let knockInterval = defaults.object(forKey: Keys.legacyKnockInterval) as? Int ?? 300
        let vpnServer = defaults.string(forKey: Keys.legacyVpnServer) ?? ""
        let vpnUsername = defaults.string(forKey: Keys.legacyVpnUsername) ?? ""

        accounts = decoded.map { account in
            var a = account
            a.knockEnabled = knockEnabled
            a.knockURL = knockURL
            a.knockIntervalMinutes = knockInterval
            a.vpnServer = vpnServer
            a.vpnUsername = vpnUsername
            return a
        }
        for account in accounts where knockEnabled {
            setKnockToken(knockToken, for: account.id)
        }
        selectedAccountId = defaults.string(forKey: Keys.selectedAccountId).flatMap(UUID.init) ?? accounts.first?.id
    }

    /// v1 predates the accounts array entirely — a single account's fields
    /// lived directly on this object.
    private func migrateFromV1IfNeeded() {
        guard let legacyDomain = defaults.string(forKey: Keys.legacyDomain), !legacyDomain.isEmpty else { return }
        let legacyUsername = defaults.string(forKey: Keys.legacyUsername) ?? ""
        guard !legacyUsername.isEmpty else { return }
        let account = SipAccount(
            label: "",
            domain: legacyDomain,
            port: defaults.object(forKey: Keys.legacyPort) as? Int ?? 5061,
            username: legacyUsername,
            transportIsTLS: defaults.object(forKey: Keys.legacyTransport) as? Bool ?? true
        )
        let legacyPassword = KeychainStore.get(forKey: Keys.legacyPassword) ?? ""
        accounts = [account]
        selectedAccountId = account.id
        setPassword(legacyPassword, for: account.id)
    }

    private func saveAccounts() {
        if let data = try? JSONEncoder().encode(accounts) {
            defaults.set(data, forKey: Keys.accounts)
        }
        // Keep selection valid whenever the list changes.
        if selectedAccountId == nil || !accounts.contains(where: { $0.id == selectedAccountId }) {
            selectedAccountId = accounts.first?.id
        }
    }

    var selectedAccount: SipAccount? {
        accounts.first(where: { $0.id == selectedAccountId }) ?? accounts.first
    }

    var isConfigured: Bool {
        accounts.contains(where: { $0.isValid })
    }

    // MARK: - Per-account secrets (Keychain, never plaintext in UserDefaults)

    func password(for accountId: UUID) -> String {
        KeychainStore.get(forKey: "sip.password.\(accountId.uuidString)") ?? ""
    }
    func setPassword(_ value: String, for accountId: UUID) {
        KeychainStore.set(value, forKey: "sip.password.\(accountId.uuidString)")
    }

    func knockToken(for accountId: UUID) -> String {
        KeychainStore.get(forKey: "sip.knockToken.\(accountId.uuidString)") ?? ""
    }
    func setKnockToken(_ value: String, for accountId: UUID) {
        KeychainStore.set(value, forKey: "sip.knockToken.\(accountId.uuidString)")
    }

    func vpnPassword(for accountId: UUID) -> String {
        KeychainStore.get(forKey: "sip.vpnPassword.\(accountId.uuidString)") ?? ""
    }
    func setVpnPassword(_ value: String, for accountId: UUID) {
        KeychainStore.set(value, forKey: "sip.vpnPassword.\(accountId.uuidString)")
    }

    func vpnSharedSecret(for accountId: UUID) -> String {
        KeychainStore.get(forKey: "sip.vpnSharedSecret.\(accountId.uuidString)") ?? ""
    }
    func setVpnSharedSecret(_ value: String, for accountId: UUID) {
        KeychainStore.set(value, forKey: "sip.vpnSharedSecret.\(accountId.uuidString)")
    }

    func removeAllSecrets(for accountId: UUID) {
        setPassword("", for: accountId)
        setKnockToken("", for: accountId)
        setVpnPassword("", for: accountId)
        setVpnSharedSecret("", for: accountId)
    }
}

/// Minimal Keychain wrapper — credentials never belong in UserDefaults.
enum KeychainStore {
    static func set(_ value: String, forKey key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var attributes = query
        attributes[kSecValueData as String] = data
        // Explicit, restrictive class: never syncs to iCloud, unreadable before first unlock.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func get(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
