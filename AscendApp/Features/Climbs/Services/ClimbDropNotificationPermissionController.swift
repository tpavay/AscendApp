import UIKit
import UserNotifications

@MainActor
enum ClimbDropNotificationPermissionController {
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await PushNotificationService.shared.authorizationStatus()
    }

    /// Requests permission from the onboarding opt-in screen. Unlike `enable`, a prior
    /// denial must never deep-link to system settings — leaving the app mid-onboarding
    /// strands the flow.
    @discardableResult
    static func requestDuringOnboarding() async -> UNAuthorizationStatus {
        await PushNotificationService.shared.requestClimbDropNotifications(opensSettingsWhenDenied: false)
    }

    @discardableResult
    static func enable() async -> UNAuthorizationStatus {
        await PushNotificationService.shared.requestClimbDropNotifications(opensSettingsWhenDenied: true)
    }

    static func disable() async {
        await PushNotificationService.shared.disableClimbDropNotifications()
    }

    static func openSystemNotificationSettings() {
        PushNotificationService.shared.openSystemNotificationSettings()
    }
}
