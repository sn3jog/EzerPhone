import Foundation

/// Per-installation settings. Replace the placeholders with your own server before
/// building; nothing here is a SIP credential.
enum SecretsConfig {
    /// Base URL of the helper service that sits next to your PBX
    /// (provision.php, knock.php, logupload.php), without a trailing slash.
    static let serverBase = "https://pbx.example.com:8443"

    /// Gate for the debug log-upload endpoint. Leave empty to disable log upload.
    static let logUploadToken = ""
}
