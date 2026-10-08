import Foundation

/// Ships the current linphone debug log to our own PBX VM after a call or
/// registration failure, so it can be pulled for debugging without needing
/// the phone physically connected to a Mac. Runs in DEBUG builds only.
enum LogUploadService {
    private static let endpoint = SecretsConfig.serverBase + "/logupload.php"

    // Registration retries can fire every few seconds — without a cooldown
    // a flaky account would flood the server with near-duplicate uploads.
    private static let cooldown: TimeInterval = 120
    private static var lastUploadAt: Date?

    /// A random, anonymous per-install identifier — not the user's device
    /// name — just enough to tell one phone's logs apart from another's.
    private static var installId: String {
        let key = "logUpload.installId"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let fresh = UUID().uuidString.prefix(8).lowercased()
        UserDefaults.standard.set(String(fresh), forKey: key)
        return String(fresh)
    }

    static func uploadCurrentLog(reason: String) {
        #if DEBUG
        guard !SecretsConfig.logUploadToken.isEmpty else { return }
        if let last = lastUploadAt, Date().timeIntervalSince(last) < cooldown { return }
        guard let path = currentLogPath(),
              let data = FileManager.default.contents(atPath: path),
              !data.isEmpty else { return }
        lastUploadAt = Date()

        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            URLQueryItem(name: "t", value: SecretsConfig.logUploadToken),
            URLQueryItem(name: "device", value: installId),
            URLQueryItem(name: "reason", value: reason)
        ]
        guard let url = components?.url else { return }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.httpBody = data
        URLSession.shared.dataTask(with: request).resume()
        #endif
    }

    private static func currentLogPath() -> String? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("linphone1.log")
            .path
    }
}
