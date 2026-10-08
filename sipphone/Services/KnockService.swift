import Foundation

/// Calls a "knock" HTTPS endpoint that whitelists this device's current
/// public IP in a MikroTik address-list before SIP registration. Each SIP
/// account has its own knock config, since accounts can live behind
/// different routers.
enum KnockService {
    enum KnockError: Error {
        case notConfigured
        case http(Int)
        case transport(Error)
    }

    @discardableResult
    static func knock(url urlString: String, token: String) async -> Result<Void, KnockError> {
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            return .failure(.notConfigured)
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.http(-1))
            }
            guard (200..<300).contains(http.statusCode) else {
                return .failure(.http(http.statusCode))
            }
            return .success(())
        } catch {
            return .failure(.transport(error))
        }
    }
}
