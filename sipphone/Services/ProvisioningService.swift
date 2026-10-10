import Foundation
import SwiftUI
import Combine

/// One-tap account setup. The PBX hands out a link whose only content is a random
/// one-time token; opening it trades that token for the account's settings over HTTPS.
/// The server address is fixed here on purpose: a link must never be able to point
/// the app at some other server.
@MainActor
final class ProvisioningService: ObservableObject {
    static let shared = ProvisioningService()

    enum State: Equatable {
        case idle
        case working
        case done(String)
        case failed(String)
    }

    @Published var state: State = .idle

    private static let endpoint = URL(string: SecretsConfig.serverBase + "/provision.php")!

    private struct Response: Decodable {
        struct Knock: Decodable {
            let url: String
            let token: String
            let interval: Int
        }
        let label: String
        let domain: String
        let port: Int
        let username: String
        let password: String
        let tls: Bool
        let srtp: Bool
        let knock: Knock?
    }

    /// `ezerphone://setup?t=<token>`
    func handle(url: URL) {
        guard url.scheme == "ezerphone", url.host == "setup",
              let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "t" })?.value,
              !token.isEmpty else {
            return
        }
        state = .working
        Task { await redeem(token: token) }
    }

    private func redeem(token: String) async {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["t": token])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch code {
            case 200:
                let config = try JSONDecoder().decode(Response.self, from: data)
                apply(config)
                state = .done(config.label.isEmpty ? config.username : config.label)
            case 410:
                state = .failed(tr("Ссылка устарела. Попросите прислать новую."))
            default:
                state = .failed(tr("Ссылка уже использована или неверна. Попросите прислать новую."))
            }
        } catch {
            state = .failed(tr("Не удалось связаться с сервером. Проверьте интернет и нажмите на ссылку ещё раз."))
        }
    }

    private func apply(_ config: Response) {
        let settings = SipSettings.shared
        let id: UUID
        // Opening a second link for the same number refreshes it instead of adding a twin.
        if let idx = settings.accounts.firstIndex(where: { $0.username == config.username && $0.domain == config.domain }) {
            id = settings.accounts[idx].id
            settings.accounts[idx].label = config.label
            settings.accounts[idx].port = config.port
            settings.accounts[idx].transportIsTLS = config.tls
            settings.accounts[idx].requireSRTP = config.srtp
            settings.accounts[idx].enabled = true
            apply(knock: config.knock, toIndex: idx, settings: settings)
        } else {
            var account = SipAccount(
                label: config.label, domain: config.domain, port: config.port,
                username: config.username, transportIsTLS: config.tls, requireSRTP: config.srtp)
            id = account.id
            if let knock = config.knock {
                account.knockEnabled = true
                account.knockURL = knock.url
                account.knockIntervalMinutes = knock.interval
            }
            settings.accounts.append(account)
        }
        settings.setPassword(config.password, for: id)
        if let knock = config.knock { settings.setKnockToken(knock.token, for: id) }
        if settings.selectedAccountId == nil { settings.selectedAccountId = id }
        AppCoordinator.shared.settingsDidChange()
    }

    private func apply(knock: Response.Knock?, toIndex idx: Int, settings: SipSettings) {
        guard let knock else { return }
        settings.accounts[idx].knockEnabled = true
        settings.accounts[idx].knockURL = knock.url
        settings.accounts[idx].knockIntervalMinutes = knock.interval
    }
}

/// Large, plain-language sheet shown while a setup link is being applied.
struct ProvisioningSheet: View {
    @ObservedObject var service: ProvisioningService

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            switch service.state {
            case .idle, .working:
                ProgressView().controlSize(.large).tint(Ink.ink)
                Text("Настраиваю аккаунт…")
                    .font(.ink(24, .bold, relativeTo: .title2))
            case .done(let name):
                InkStatusMark(kind: .registered, size: 72, isDefault: true)
                Text("Готово!")
                    .font(.ink(30, .bold, relativeTo: .title))
                Text("Аккаунт «\(name)» добавлен. Можно звонить.")
                    .font(.ink(20, .italic, relativeTo: .title3))
                    .multilineTextAlignment(.center)
            case .failed(let text):
                InkStatusMark(kind: .failed, size: 72)
                Text("Не получилось")
                    .font(.ink(30, .bold, relativeTo: .title))
                Text(text)
                    .font(.ink(20, .italic, relativeTo: .title3))
                    .multilineTextAlignment(.center)
            }
            Spacer()
            if service.state != .working {
                InkWideButton(title: "Закрыть") { service.state = .idle }
            }
        }
        .foregroundStyle(Ink.ink)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .inkPaper()
        .interactiveDismissDisabled(service.state == .working)
    }
}
