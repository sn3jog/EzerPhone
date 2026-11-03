#if DEBUG
import Foundation

/// App Store screenshots. Launched with `-screenshots <screen>` (keypad, favorites, recents,
/// contacts, settings, call), a Debug build fills itself with made-up accounts, contacts and
/// calls, shows the accounts as registered and never touches the network. Theme and language
/// come from the usual defaults, which launch arguments override: `-app.theme classicDark`,
/// `-app.language en`.
enum ScreenshotMode {
    static let screen: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screenshots") else { return nil }
        return args.indices.contains(i + 1) ? args[i + 1] : "keypad"
    }()

    static var isOn: Bool { screen != nil }

    @MainActor
    static func seed() {
        let office = SipAccount(label: "Office", domain: "pbx.example.com", port: 5061,
                                username: "204", transportIsTLS: true, requireSRTP: true)
        let provider = SipAccount(label: "Provider", domain: "sip.example.net", port: 5060,
                                  username: "4951730", transportIsTLS: false)
        var home = SipAccount(label: "Home", domain: "home.example.org", port: 5060,
                              username: "12", transportIsTLS: false)
        home.enabled = false
        let settings = SipSettings.shared
        settings.accounts = [office, provider, home]
        settings.selectedAccountId = office.id

        ContactsStore.shared.contacts = [
            PhoneContact(name: "Anna Berg", number: "+49 30 5550 1842", isFavorite: true),
            PhoneContact(name: "David Cohen", number: "+972 3 555 0199", isFavorite: true),
            PhoneContact(name: "Reception", number: "100", isFavorite: true),
            PhoneContact(name: "Elena Sorokina", number: "+371 6555 0147"),
            PhoneContact(name: "Kenji Watanabe", number: "+81 3 5550 7312"),
            PhoneContact(name: "Lucía Moreno", number: "+34 915 550 284"),
            PhoneContact(name: "Mark Tamm", number: "+372 555 0163"),
            PhoneContact(name: "Support desk", number: "205"),
        ]

        let history = CallHistoryStore.shared
        history.clear()
        let now = Date()
        let calls: [(String, CallHistoryEntry.Direction, TimeInterval, Int)] = [
            ("+34 915 550 284", .incoming, 2 * 86_400, 412),
            ("205", .outgoing, 30 * 3_600, 95),
            ("+81 3 5550 7312", .missed, 26 * 3_600, 0),
            ("+972 3 555 0199", .outgoing, 5 * 3_600, 1_268),
            ("100", .incoming, 2 * 3_600, 64),
            ("+49 30 5550 1842", .outgoing, 25 * 60, 187),
        ]
        for (remote, direction, ago, duration) in calls {
            history.add(CallHistoryEntry(remote: remote, direction: direction,
                                         date: now.addingTimeInterval(-ago), durationSeconds: duration))
        }

        LinphoneManager.shared.showAsRegistered([office.id, provider.id],
                                                callingTo: screen == "call" ? "Anna Berg" : nil)
    }
}
#endif
