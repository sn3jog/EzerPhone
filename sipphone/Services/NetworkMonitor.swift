import Network
import Foundation
import Combine

/// Watches for Wi-Fi <-> cellular transitions and any other path change,
/// so the app can re-knock and re-register without user action.
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isConnected: Bool = true
    @Published private(set) var isExpensive: Bool = false

    /// Called on every meaningful path change (after the very first one).
    var onPathChange: (() -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "info.ezer.sipphone.netmonitor")
    private var lastPath: (connected: Bool, expensive: Bool, interfaces: [NWInterface.InterfaceType])?

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let connected = path.status == .satisfied
            let expensive = path.isExpensive
            let interfaces = path.availableInterfaces.map(\.type)
            DispatchQueue.main.async {
                self.isConnected = connected
                self.isExpensive = expensive
            }
            // NWPathMonitor reports every path update, including ones that change
            // nothing we care about (route/DNS churn fires it every few seconds).
            // Re-registering on those tore down every account, killing calls that
            // were still being set up.
            let previous = self.lastPath
            self.lastPath = (connected, expensive, interfaces)
            guard let previous else { return }
            if previous.connected != connected
                || previous.expensive != expensive
                || previous.interfaces != interfaces {
                self.onPathChange?()
            }
        }
        monitor.start(queue: queue)
    }
}
