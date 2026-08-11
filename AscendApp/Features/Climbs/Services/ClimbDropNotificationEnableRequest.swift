import UserNotifications

/// One climb-drop enable request, start to finish.
///
/// The order is the contract. The climber's answer is written to the device first and
/// synchronously, so it survives a dropped connection, a suspension, or a termination. The route
/// into iOS Settings opens next, because a tap that asked for a screen cannot wait out two
/// callables to get there. The server hears about both last - eventually, and again on the next
/// foreground, which is exactly when a climber returning from iOS Settings comes back.
@MainActor
struct ClimbDropNotificationEnableRequest {
    var currentAuthorizationStatus: @MainActor () async -> UNAuthorizationStatus
    var presentSystemAuthorizationAlert: @MainActor () async -> UNAuthorizationStatus
    var recordIntent: @MainActor (Bool) -> Void
    var openSystemNotificationSettings: @MainActor () -> Void
    var synchronizeInBackground: @MainActor (UNAuthorizationStatus) -> Void

    func run(opensSettingsWhenDenied: Bool) async -> UNAuthorizationStatus {
        let initialStatus = await currentAuthorizationStatus()
        let status = initialStatus == .notDetermined
            ? await presentSystemAuthorizationAlert()
            : initialStatus

        let decision = ClimbDropNotificationIntentPolicy.decision(
            initialStatus: initialStatus,
            resolvedStatus: status
        )
        if case .record(let isEnabled) = decision {
            recordIntent(isEnabled)
        }

        let routesToSystemSettings = ClimbDropNotificationIntentPolicy.routesToSystemSettings(
            initialStatus: initialStatus,
            resolvedStatus: status
        )
        if opensSettingsWhenDenied, routesToSystemSettings {
            openSystemNotificationSettings()
        }

        synchronizeInBackground(status)
        return status
    }
}
