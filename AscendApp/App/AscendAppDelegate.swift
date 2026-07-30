import UIKit
@preconcurrency import UserNotifications
@preconcurrency import FirebaseMessaging

final class AscendAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = PushNotificationCenterDelegate.shared
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        #if DEBUG
        guard !ReturningSubscriberJourneyUITestScenario.isRequested else { return }
        #endif

        Messaging.messaging().apnsToken = deviceToken
        Task { @MainActor in
            await PushNotificationService.shared.synchronizeAuthenticatedDeviceIfNeeded()
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        TelemetryManager.shared.recordError(
            error,
            context: .network,
            code: "push_apns_registration_failed"
        )
    }
}

final class PushNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = PushNotificationCenterDelegate()

    private override init() {
        super.init()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            PushNotificationRouter.shared.route(from: userInfo)
        }
        completionHandler()
    }
}
