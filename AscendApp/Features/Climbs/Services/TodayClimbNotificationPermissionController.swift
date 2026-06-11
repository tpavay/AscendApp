import UIKit
import UserNotifications

@MainActor
enum TodayClimbNotificationPermissionController {
    static func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        LifecycleEventRecorder.shared.recordNotificationPermission(status: settings.authorizationStatus)
        return settings.authorizationStatus
    }

    /// Requests permission from the onboarding opt-in screen. Unlike `enable`, a prior
    /// denial must never deep-link to system settings — leaving the app mid-onboarding
    /// strands the flow.
    @discardableResult
    static func requestDuringOnboarding() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        LifecycleEventRecorder.shared.recordNotificationPermission(status: settings.authorizationStatus)

        switch settings.authorizationStatus {
        case .notDetermined:
            _ = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            let updatedSettings = await center.notificationSettings()
            LifecycleEventRecorder.shared.recordNotificationPermission(status: updatedSettings.authorizationStatus)

            let isEnabled = allowsTodayClimbNotifications(updatedSettings.authorizationStatus)
            TodayClimbNotificationPreferenceStore.isEnabled = isEnabled
            if !isEnabled {
                await TodayClimbNotificationScheduler.shared.cancelPendingTodayClimbNotifications()
            }
            return updatedSettings.authorizationStatus

        case .authorized, .provisional, .ephemeral:
            TodayClimbNotificationPreferenceStore.isEnabled = true
            return settings.authorizationStatus

        case .denied:
            TodayClimbNotificationPreferenceStore.isEnabled = false
            await TodayClimbNotificationScheduler.shared.cancelPendingTodayClimbNotifications()
            return settings.authorizationStatus

        @unknown default:
            TodayClimbNotificationPreferenceStore.isEnabled = false
            await TodayClimbNotificationScheduler.shared.cancelPendingTodayClimbNotifications()
            return settings.authorizationStatus
        }
    }

    @discardableResult
    static func enable(
        availableClimbs: [Climb],
        completedClimbIds: Set<String>
    ) async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        LifecycleEventRecorder.shared.recordNotificationPermission(status: settings.authorizationStatus)

        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            let updatedSettings = await center.notificationSettings()
            LifecycleEventRecorder.shared.recordNotificationPermission(status: updatedSettings.authorizationStatus)

            guard granted else {
                TodayClimbNotificationPreferenceStore.isEnabled = false
                await TodayClimbNotificationScheduler.shared.cancelPendingTodayClimbNotifications()
                return updatedSettings.authorizationStatus
            }

            TodayClimbNotificationPreferenceStore.isEnabled = true
            await TodayClimbNotificationScheduler.shared.scheduleIfAuthorized(
                availableClimbs: availableClimbs,
                completedClimbIds: completedClimbIds
            )
            return updatedSettings.authorizationStatus

        case .authorized, .provisional, .ephemeral:
            TodayClimbNotificationPreferenceStore.isEnabled = true
            await TodayClimbNotificationScheduler.shared.scheduleIfAuthorized(
                availableClimbs: availableClimbs,
                completedClimbIds: completedClimbIds
            )
            return settings.authorizationStatus

        case .denied:
            TodayClimbNotificationPreferenceStore.isEnabled = false
            await TodayClimbNotificationScheduler.shared.cancelPendingTodayClimbNotifications()
            openSystemNotificationSettings()
            return settings.authorizationStatus

        @unknown default:
            TodayClimbNotificationPreferenceStore.isEnabled = false
            await TodayClimbNotificationScheduler.shared.cancelPendingTodayClimbNotifications()
            return settings.authorizationStatus
        }
    }

    static func disable() async {
        TodayClimbNotificationPreferenceStore.isEnabled = false
        await TodayClimbNotificationScheduler.shared.cancelPendingTodayClimbNotifications()
    }

    static func openSystemNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private static func allowsTodayClimbNotifications(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }
}
