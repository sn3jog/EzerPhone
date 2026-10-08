import Foundation

struct SipAccount: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var label: String
    var domain: String
    var port: Int
    var username: String
    var transportIsTLS: Bool
    var enabled: Bool = true

    // Media encryption. Some providers (Zadarma) answer "488 SRTP required" to a
    // plain RTP offer; the internal PBX is configured for plain RTP, so this has
    // to be per account rather than one global setting.
    var requireSRTP: Bool = false

    // Access ("knock") — per account, since each account may live behind a
    // different router/IP-allowlist.
    var knockEnabled: Bool = false
    var knockURL: String = ""
    var knockIntervalMinutes: Int = 300

    // VPN — per account. Requires a paid Apple Developer account (Personal
    // VPN capability isn't available on free/Personal Team signing), so the
    // UI keeps this disabled until that's in place.
    var vpnEnabled: Bool = false
    var vpnServer: String = ""
    var vpnUsername: String = ""

    // Custom decoding: accounts saved before requireSRTP existed have no such key,
    // and the synthesized decoder would reject them — silently emptying the list.
    private enum CodingKeys: String, CodingKey {
        case id, label, domain, port, username, transportIsTLS, enabled, requireSRTP
        case knockEnabled, knockURL, knockIntervalMinutes
        case vpnEnabled, vpnServer, vpnUsername
    }

    init(id: UUID = UUID(), label: String, domain: String, port: Int, username: String,
         transportIsTLS: Bool, enabled: Bool = true, requireSRTP: Bool = false) {
        self.id = id
        self.label = label
        self.domain = domain
        self.port = port
        self.username = username
        self.transportIsTLS = transportIsTLS
        self.enabled = enabled
        self.requireSRTP = requireSRTP
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try c.decode(String.self, forKey: .label)
        domain = try c.decode(String.self, forKey: .domain)
        port = try c.decode(Int.self, forKey: .port)
        username = try c.decode(String.self, forKey: .username)
        transportIsTLS = try c.decode(Bool.self, forKey: .transportIsTLS)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        requireSRTP = try c.decodeIfPresent(Bool.self, forKey: .requireSRTP) ?? false
        knockEnabled = try c.decodeIfPresent(Bool.self, forKey: .knockEnabled) ?? false
        knockURL = try c.decodeIfPresent(String.self, forKey: .knockURL) ?? ""
        knockIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .knockIntervalMinutes) ?? 300
        vpnEnabled = try c.decodeIfPresent(Bool.self, forKey: .vpnEnabled) ?? false
        vpnServer = try c.decodeIfPresent(String.self, forKey: .vpnServer) ?? ""
        vpnUsername = try c.decodeIfPresent(String.self, forKey: .vpnUsername) ?? ""
    }

    var displayName: String {
        label.isEmpty ? username : label
    }

    var isValid: Bool {
        !domain.isEmpty && !username.isEmpty
    }
}
