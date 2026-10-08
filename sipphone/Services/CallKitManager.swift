import CallKit
import AVFoundation
import Foundation

/// Bridges LinphoneManager call events to the system CallKit UI
/// (lock-screen incoming call, system call screen, Phone-app recents entry).
final class CallKitManager: NSObject {
    static let shared = CallKitManager()

    private let provider: CXProvider
    private let callController = CXCallController()
    private var currentCallUUID: UUID?

    private override init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = false
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]
        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    func reportIncomingCall(remote: String, callId: String) {
        let uuid = UUID()
        currentCallUUID = uuid
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: remote)
        update.hasVideo = false
        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            if let error {
                print("CallKit incoming report failed: \(error)")
            }
        }
    }

    func reportCallEnded(reason: CXCallEndedReason = .remoteEnded) {
        guard let uuid = currentCallUUID else { return }
        provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
        currentCallUUID = nil
    }

    private var pendingOutgoingDestination: String?
    private var pendingOutgoingAccountId: UUID?

    func startOutgoingCall(remote: String, accountId: UUID?) {
        let uuid = UUID()
        currentCallUUID = uuid
        pendingOutgoingDestination = remote
        pendingOutgoingAccountId = accountId
        let handle = CXHandle(type: .generic, value: remote)
        let action = CXStartCallAction(call: uuid, handle: handle)
        callController.request(CXTransaction(action: action)) { error in
            if let error {
                print("CallKit start call failed: \(error)")
            }
        }
    }

    func reportOutgoingCallConnected() {
        guard let uuid = currentCallUUID else { return }
        provider.reportOutgoingCall(with: uuid, connectedAt: Date())
    }

    func endCurrentCall() {
        guard let uuid = currentCallUUID else { return }
        let action = CXEndCallAction(call: uuid)
        callController.request(CXTransaction(action: action)) { _ in }
    }
}

extension CallKitManager: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        LinphoneManager.shared.hangup()
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        guard let destination = pendingOutgoingDestination else {
            action.fail()
            return
        }
        pendingOutgoingDestination = nil
        let accountId = pendingOutgoingAccountId
        pendingOutgoingAccountId = nil
        if LinphoneManager.shared.call(destination, fromAccountId: accountId) {
            provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
            action.fulfill()
        } else {
            action.fail()
        }
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        LinphoneManager.shared.answer()
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        LinphoneManager.shared.hangup()
        action.fulfill()
        currentCallUUID = nil
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        LinphoneManager.shared.setMuted(action.isMuted)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        // linphone-sdk only opens mic/speaker once told the CallKit session is live —
        // without this, outgoing calls connect but stay silent in both directions.
        LinphoneManager.shared.setAudioSessionActivated(true)
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        LinphoneManager.shared.setAudioSessionActivated(false)
    }
}
