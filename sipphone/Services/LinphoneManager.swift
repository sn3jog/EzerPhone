import Foundation
import Combine
import linphonesw

/// Thin wrapper around linphone-sdk's Core. Owns SIP registration for one or
/// more accounts and exposes just what the UI/CallKit layers need.
///
/// NOTE: the linphonesw API surface below matches the SDK's documented
/// Swift wrapper as of 5.3.x. If a future SDK version renames something,
/// this is the only file that needs to change.
final class LinphoneManager: NSObject, ObservableObject {
    static let shared = LinphoneManager()

    enum RegState: String {
        case none, progress, ok, failed, cleared
    }

    @Published private(set) var registrationStates: [UUID: RegState] = [:]
    @Published private(set) var registrationErrors: [UUID: String] = [:]
    @Published private(set) var activeCallRemote: String?
    @Published private(set) var activeCallIsIncoming = false
    /// SIP status of the last failed call ("403 Forbidden"), so a provider's
    /// rejection is visible instead of the call just vanishing.
    @Published private(set) var lastCallError: String?

    /// What is currently registered, so an unchanged set can refresh in place.
    private var registeredAccounts: [SipAccount] = []

    /// Aggregate state for the simple status banner: best state wins.
    var registrationState: RegState {
        if registrationStates.values.contains(.ok) { return .ok }
        if registrationStates.values.contains(.progress) { return .progress }
        if registrationStates.values.contains(.failed) { return .failed }
        return .none
    }
    var registrationError: String? { registrationErrors.values.first }

    private var core: Core!
    private var iterateTimer: Timer?
    private var coreDelegate: CoreDelegate?

    private var linphoneAccountsById: [UUID: Account] = [:]
    private var accountIdByObjectId: [ObjectIdentifier: UUID] = [:]
    private var accountsById: [UUID: SipAccount] = [:]

    var onIncomingCall: ((_ remote: String, _ callId: String) -> Void)?
    var onCallEnded: ((_ remote: String, _ wasIncoming: Bool, _ duration: Int) -> Void)?
    var onCallConnected: ((_ remote: String) -> Void)?

    private override init() {
        super.init()
        setupCore()
    }

    private func setupCore() {
        do {
            let factory = Factory.Instance
            #if DEBUG
            // SDK logs can contain SIP credentials/SDP in plaintext — never collect
            // them in Release, and keep them out of device/iCloud backups.
            var logDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("logs", isDirectory: true)
            try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
            var noBackup = URLResourceValues()
            noBackup.isExcludedFromBackup = true
            try? logDir.setResourceValues(noBackup)
            Core.setLogCollectionPath(path: logDir.path)
            Core.enableLogCollection(state: .Enabled)
            // Without this the collected log holds only warnings and errors — no
            // SIP messages or SDP — which makes a provider's rejection
            // indistinguishable from a local failure.
            LoggingService.Instance.logLevel = .Debug
            #else
            Core.enableLogCollection(state: .Disabled)
            #endif

            core = try factory.createCore(configPath: "", factoryConfigPath: "", systemContext: nil)
            core.autoIterateEnabled = false // we drive iterate() ourselves so timing is explicit
            // The SDK's built-in root CA path is the one on the machine it was built on
            // (/opt/homebrew/...), which doesn't exist on a phone, so TLS had nothing to
            // check server certificates against. The same CA list ships inside linphone.framework.
            if let rootCa = Bundle.main.privateFrameworksURL?.appendingPathComponent("linphone.framework/rootca.pem"),
               FileManager.default.fileExists(atPath: rootCa.path) {
                core.rootCa = rootCa.path
            }
            // Without this, the SDK rejects our CallKit didActivate/didDeactivate
            // audio session signals ("not in Callkit mode: application mistake")
            // and never opens the mic/speaker on outgoing calls.
            core.callkitEnabled = true

            let delegate = CoreDelegateStub(
                onRegistrationStateChanged: { [weak self] _, account, state, message in
                    self?.handleRegistrationState(account: account, state, message: message)
                },
                onCallStateChanged: { [weak self] _, call, state, message in
                    self?.handleCallState(call: call, state: state, message: message)
                }
            )
            core.addDelegate(delegate: delegate)
            self.coreDelegate = delegate

            try core.start()
            startIterate()
        } catch {
            registrationErrors[UUID()] = "Core init failed: \(error)"
        }
    }

    private func startIterate() {
        iterateTimer?.invalidate()
        iterateTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            self?.core.iterate()
        }
        RunLoop.current.add(iterateTimer!, forMode: .common)
    }

    // MARK: - Registration (multi-account)

    #if DEBUG
    /// Screenshot mode only (`ScreenshotMode`): shows accounts as registered, and optionally
    /// a call in progress, without any SIP traffic.
    func showAsRegistered(_ ids: [UUID], callingTo remote: String?) {
        for id in ids { registrationStates[id] = .ok }
        activeCallRemote = remote
        activeCallIsIncoming = false
    }
    #endif

    func register(accounts: [SipAccount], settingsStore: SipSettings) {
        // Rebuilding destroys every Account object, and any call riding on one
        // dies with it. The re-knock timer, foreground and path changes all land
        // here, so refresh instead whenever the set is unchanged.
        if accounts == registeredAccounts, !linphoneAccountsById.isEmpty {
            core.refreshRegisters()
            return
        }
        // A genuine change during a call waits: the next trigger re-applies it.
        guard core.currentCall == nil else { return }

        core.clearAccounts()
        core.clearAllAuthInfo()
        linphoneAccountsById.removeAll()
        accountIdByObjectId.removeAll()
        accountsById.removeAll()
        registrationStates.removeAll()
        registrationErrors.removeAll()

        for account in accounts {
            guard account.enabled, account.isValid else { continue }
            let password = settingsStore.password(for: account.id)
            guard !password.isEmpty else { continue }
            do {
                let transport: TransportType = account.transportIsTLS ? .Tls : .Udp
                let identity = try Factory.Instance.createAddress(addr: "sip:\(account.username)@\(account.domain)")

                let authInfo = try Factory.Instance.createAuthInfo(
                    username: account.username,
                    userid: "",
                    passwd: password,
                    ha1: "",
                    realm: "",
                    domain: account.domain
                )
                core.addAuthInfo(info: authInfo)

                let params = try core.createAccountParams()
                try params.setIdentityaddress(newValue: identity)

                let serverAddr = try Factory.Instance.createAddress(addr: "sip:\(account.domain):\(account.port)")
                try serverAddr.setTransport(newValue: transport)
                try params.setServeraddress(newValue: serverAddr)
                params.registerEnabled = true
                params.expires = 3600

                let linphoneAccount = try core.createAccount(params: params)
                try core.addAccount(account: linphoneAccount)

                linphoneAccountsById[account.id] = linphoneAccount
                accountIdByObjectId[ObjectIdentifier(linphoneAccount)] = account.id
                accountsById[account.id] = account
                registrationStates[account.id] = .progress

                if core.defaultAccount == nil || account.id == settingsStore.selectedAccountId {
                    core.defaultAccount = linphoneAccount
                }
            } catch {
                registrationErrors[account.id] = "\(error)"
                registrationStates[account.id] = .failed
            }
        }
        registeredAccounts = accounts
    }

    func unregister() {
        core.clearAccounts()
        registeredAccounts = []
        linphoneAccountsById.removeAll()
        accountIdByObjectId.removeAll()
        accountsById.removeAll()
        registrationStates.removeAll()
        registrationErrors.removeAll()
    }

    /// Must be called from CXProviderDelegate's didActivate/didDeactivate —
    /// linphone-sdk only opens the mic/speaker once CallKit's audio session
    /// is confirmed active (this is what made outgoing calls silent).
    func setAudioSessionActivated(_ activated: Bool) {
        core.activateAudioSession(activated: activated)
    }

    private func handleRegistrationState(account: Account, _ state: RegistrationState, message: String) {
        guard let id = accountIdByObjectId[ObjectIdentifier(account)] else { return }
        DispatchQueue.main.async {
            switch state {
            case .Ok: self.registrationStates[id] = .ok; self.registrationErrors[id] = nil
            case .Progress: self.registrationStates[id] = .progress
            case .Failed:
                self.registrationStates[id] = .failed
                self.registrationErrors[id] = message
                LogUploadService.uploadCurrentLog(reason: "reg-failed")
            case .Cleared: self.registrationStates[id] = .cleared
            default: self.registrationStates[id] = .none
            }
        }
    }

    // MARK: - Calling

    @discardableResult
    func call(_ destination: String, fromAccountId: UUID?) -> Bool {
        guard let id = fromAccountId ?? accountsById.keys.first,
              let linphoneAccount = linphoneAccountsById[id],
              let account = accountsById[id] else {
            return false
        }
        core.defaultAccount = linphoneAccount
        // A destination with spaces/dashes (e.g. pasted from somewhere as
        // "+371 2 2105594") makes an invalid SIP URI — createAddress then
        // fails and this silently returns false with no call ever starting.
        let cleaned = destination.dialSanitized
        guard !cleaned.isEmpty,
              let addr = try? Factory.Instance.createAddress(addr: "sip:\(cleaned)@\(account.domain)") else {
            return false
        }
        guard let params = try? core.createCallParams(call: nil) else { return false }
        // Plain RTP for the internal PBX; SRTP where the provider insists on it
        // (Zadarma answers a plain offer with "488 SRTP required").
        params.mediaEncryption = account.requireSRTP ? .SRTP : .None
        _ = core.inviteAddressWithParams(addr: addr, params: params)
        return true
    }

    func answer() {
        guard let call = core.currentCall else { return }
        let params = try? core.createCallParams(call: call)
        try? call.acceptWithParams(params: params)
    }

    func decline() {
        try? core.currentCall?.decline(reason: .Declined)
    }

    func hangup() {
        try? core.currentCall?.terminate()
    }

    /// Sends a keypad tone into the active call (RFC 4733), for voice menus and PINs.
    func sendDtmf(_ digit: Character) {
        guard let call = core.currentCall, let ascii = digit.asciiValue else { return }
        try? call.sendDtmf(dtmf: CChar(ascii))
    }

    func setMuted(_ muted: Bool) {
        core.micEnabled = !muted
    }

    func setSpeaker(_ on: Bool) {
        // AudioDevice routing — actual device list depends on hardware;
        // this picks the first speaker/earpiece match.
        guard let devices = core.audioDevices as [AudioDevice]? else { return }
        let wanted = on ? AudioDevice.Kind.Speaker : AudioDevice.Kind.Earpiece
        if let device = devices.first(where: { $0.type == wanted }) {
            core.currentCall?.outputAudioDevice = device
        }
    }

    private func handleCallState(call: Call, state: Call.State, message: String) {
        DispatchQueue.main.async {
            let remote = call.remoteAddress?.username ?? "unknown"
            switch state {
            case .OutgoingInit, .OutgoingProgress, .OutgoingRinging, .OutgoingEarlyMedia:
                // Show the call screen as soon as we start dialing out, not only
                // once it connects — otherwise a call that's still ringing (e.g.
                // to an outside number through a slower provider) looks like it
                // never started.
                self.activeCallRemote = remote
                self.activeCallIsIncoming = false
            case .IncomingReceived:
                self.activeCallRemote = remote
                self.activeCallIsIncoming = true
                self.onIncomingCall?(remote, call.callLog?.callId ?? UUID().uuidString)
            case .Connected:
                self.activeCallRemote = remote
                // CallKit's CXProvider.reportOutgoingCall(connectedAt:) must fire on
                // answer, or newer iOS can leave the outgoing leg's audio session
                // unrouted even though signaling succeeded (silent call).
                self.onCallConnected?(remote)
            case .StreamsRunning:
                self.activeCallRemote = remote
            case .Error:
                let code = call.errorInfo?.protocolCode ?? 0
                let phrase = call.errorInfo?.phrase ?? message
                self.lastCallError = code > 0 ? "\(code) \(phrase)" : phrase
                LogUploadService.uploadCurrentLog(reason: "call-\(code)")
                let duration = Int(call.duration)
                self.onCallEnded?(remote, self.activeCallIsIncoming, duration)
                self.activeCallRemote = nil
                self.activeCallIsIncoming = false
            case .End, .Released:
                let duration = Int(call.duration)
                self.onCallEnded?(remote, self.activeCallIsIncoming, duration)
                self.activeCallRemote = nil
                self.activeCallIsIncoming = false
            default:
                break
            }
        }
    }
}

/// linphonesw's CoreDelegate is a protocol with many optional-ish methods;
/// this stub forwards only what we use via closures for readability.
private final class CoreDelegateStub: CoreDelegate {
    let onRegistrationStateChanged: (Core, Account, RegistrationState, String) -> Void
    let onCallStateChanged: (Core, Call, Call.State, String) -> Void

    init(
        onRegistrationStateChanged: @escaping (Core, Account, RegistrationState, String) -> Void,
        onCallStateChanged: @escaping (Core, Call, Call.State, String) -> Void
    ) {
        self.onRegistrationStateChanged = onRegistrationStateChanged
        self.onCallStateChanged = onCallStateChanged
    }

    func onAccountRegistrationStateChanged(core: Core, account: Account, state: RegistrationState, message: String) {
        onRegistrationStateChanged(core, account, state, message)
    }

    func onCallStateChanged(core: Core, call: Call, state: Call.State, message: String) {
        onCallStateChanged(core, call, state, message)
    }
}
