import Foundation
import Combine
import NetworkExtension

/// Wraps NEVPNManager to bring up the router's IPSec/IKEv2 VPN before the SIP
/// registration flow runs, as an alternative to the knock mechanism.
final class VPNManager: ObservableObject {
    static let shared = VPNManager()

    enum Status: Equatable {
        case disconnected, connecting, connected, failed(String)
    }

    @Published private(set) var status: Status = .disconnected

    private let manager = NEVPNManager.shared()
    private var statusObserver: NSObjectProtocol?

    private init() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    private func refreshStatus() {
        switch manager.connection.status {
        case .connected: status = .connected
        case .connecting, .reasserting: status = .connecting
        case .disconnecting, .disconnected, .invalid: status = .disconnected
        @unknown default: status = .disconnected
        }
    }

    /// Loads (or creates) the IKEv2 profile for one SIP account's VPN config
    /// and starts the tunnel. Awaits until connected, failed, or timeout.
    /// Not currently wired into the register flow — VPN needs a paid Apple
    /// Developer account (Personal VPN capability), see SettingsView.
    func connect(account: SipAccount, settingsStore: SipSettings) async -> Bool {
        guard !account.vpnServer.isEmpty, !account.vpnUsername.isEmpty else {
            status = .failed("VPN не настроен")
            return false
        }

        do {
            try await manager.loadFromPreferences()

            if manager.connection.status == .connected {
                status = .connected
                return true
            }

            let ike = NEVPNProtocolIKEv2()
            ike.serverAddress = account.vpnServer
            ike.remoteIdentifier = account.vpnServer
            ike.username = account.vpnUsername
            let vpnPassword = settingsStore.vpnPassword(for: account.id)
            ike.passwordReference = try storePasswordInKeychain(vpnPassword, account: "vpn-\(account.id.uuidString)")
            ike.authenticationMethod = .none
            ike.useExtendedAuthentication = true
            ike.disconnectOnSleep = false

            manager.protocolConfiguration = ike
            manager.localizedDescription = "EzerPhone VPN"
            manager.isEnabled = true
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()

            status = .connecting
            try manager.connection.startVPNTunnel()

            return await waitForConnection()
        } catch {
            status = .failed("\(error)")
            return false
        }
    }

    func disconnect() {
        manager.connection.stopVPNTunnel()
    }

    private func waitForConnection(timeout: TimeInterval = 15) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            refreshStatus()
            if status == .connected { return true }
            if case .failed = status { return false }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        status = .failed("Таймаут подключения VPN")
        return false
    }

    private func storePasswordInKeychain(_ password: String, account: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "info.ezer.sipphone.vpn",
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data(password.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "VPNManager", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain write failed (\(status))"])
        }
        var refQuery = query
        refQuery[kSecReturnPersistentRef as String] = true
        var ref: AnyObject?
        SecItemCopyMatching(refQuery as CFDictionary, &ref)
        guard let data = ref as? Data else {
            throw NSError(domain: "VPNManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Keychain ref lookup failed"])
        }
        return data
    }
}
