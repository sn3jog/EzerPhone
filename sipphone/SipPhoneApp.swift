import SwiftUI

@main
struct SipPhoneApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings = SipSettings.shared
    @StateObject private var linphone = LinphoneManager.shared
    @StateObject private var coordinator = AppCoordinator.shared

    init() {
        // On iOS 15 a List can't hide its own background, so clear it for every table.
        if #unavailable(iOS 16.0) {
            UITableView.appearance().backgroundColor = .clear
            UITableViewCell.appearance().backgroundColor = .clear
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // Parchment and ink only: a dark appearance would turn every system
                // surface (keyboard, menus, sheets) against the drawn interface.
                .preferredColorScheme(.light)
                .tint(Ink.ink)
                .environmentObject(settings)
                .environmentObject(linphone)
                .environmentObject(coordinator)
                .onAppear { coordinator.start() }
                .onOpenURL { ProvisioningService.shared.handle(url: $0) }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    coordinator.appWillEnterForeground()
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Ensure the CallKit provider exists from process launch, so it can
        // report calls even if the app was launched in the background.
        _ = CallKitManager.shared
        return true
    }
}
