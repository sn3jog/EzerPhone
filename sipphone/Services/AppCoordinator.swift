import Foundation
import Combine

/// Ties settings + network changes + per-account knock + registration
/// together. Each enabled account may knock its own URL before the whole
/// set gets registered; re-runs on network change, on a timer, and on
/// foreground.
@MainActor
final class AppCoordinator: ObservableObject {
    static let shared = AppCoordinator()

    @Published private(set) var lastKnockStatus: String = "—"
    @Published private(set) var lastKnockDate: Date?

    private var reKnockTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        NetworkMonitor.shared.onPathChange = { [weak self] in
            Task { @MainActor in self?.runRegisterFlow(reason: "network change") }
        }

        LinphoneManager.shared.onIncomingCall = { remote, callId in
            CallKitManager.shared.reportIncomingCall(remote: remote, callId: callId)
        }
        LinphoneManager.shared.onCallConnected = { _ in
            if !LinphoneManager.shared.activeCallIsIncoming {
                CallKitManager.shared.reportOutgoingCallConnected()
            }
        }
        LinphoneManager.shared.onCallEnded = { remote, wasIncoming, duration in
            CallHistoryStore.shared.add(CallHistoryEntry(
                remote: remote,
                direction: wasIncoming ? .incoming : .outgoing,
                durationSeconds: duration
            ))
            CallKitManager.shared.reportCallEnded()
        }
    }

    func start() {
        #if DEBUG
        if ScreenshotMode.isOn {
            ScreenshotMode.seed()
            return
        }
        #endif
        runRegisterFlow(reason: "app start")
        scheduleReKnock()
    }

    func appWillEnterForeground() {
        runRegisterFlow(reason: "foreground")
    }

    func settingsDidChange() {
        scheduleReKnock()
        runRegisterFlow(reason: "settings changed")
    }

    func knockNow() {
        runRegisterFlow(reason: "manual")
    }

    func placeCall(_ destination: String, accountId: UUID?) {
        guard !destination.isEmpty else { return }
        CallKitManager.shared.startOutgoingCall(remote: destination, accountId: accountId)
    }

    // MARK: - Internal

    private func runRegisterFlow(reason: String) {
        #if DEBUG
        if ScreenshotMode.isOn { return }
        #endif
        let settings = SipSettings.shared
        let activeAccounts = settings.accounts.filter { $0.enabled && $0.isValid }
        let accountsNeedingKnock = activeAccounts.filter { $0.knockEnabled && !$0.knockURL.isEmpty }

        Task {
            if !accountsNeedingKnock.isEmpty {
                let summary = await withTaskGroup(of: String.self) { group -> [String] in
                    for account in accountsNeedingKnock {
                        group.addTask {
                            let token = settings.knockToken(for: account.id)
                            let result = await KnockService.knock(url: account.knockURL, token: token)
                            switch result {
                            case .success: return "\(account.displayName): OK"
                            case .failure(let error): return "\(account.displayName): \(error)"
                            }
                        }
                    }
                    var results: [String] = []
                    for await line in group { results.append(line) }
                    return results
                }
                await MainActor.run {
                    self.lastKnockDate = Date()
                    self.lastKnockStatus = summary.joined(separator: ", ") + " (\(reason))"
                }
                // give the firewall a moment to apply the new allow-list entries
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            await MainActor.run {
                LinphoneManager.shared.register(accounts: activeAccounts, settingsStore: settings)
            }
        }
    }

    private func scheduleReKnock() {
        reKnockTimer?.invalidate()
        let minutes = SipSettings.shared.accounts
            .filter { $0.knockEnabled }
            .map { max(1, $0.knockIntervalMinutes) }
            .min() ?? 0
        guard minutes > 0 else { return }
        reKnockTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runRegisterFlow(reason: "timer") }
        }
    }
}
