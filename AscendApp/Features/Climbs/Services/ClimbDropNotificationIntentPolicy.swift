import UserNotifications

/// What an enable request means for the stored climb-drop preference.
enum ClimbDropNotificationIntentDecision: Equatable {
    /// The climber answered, and this is the answer to store.
    case record(Bool)
    /// Nothing new was chosen, so the stored intent stands.
    case preserve
}

/// Reads an enable request's outcome as the climber's intent.
///
/// Only the authorization status the request started from says whether iOS presented its
/// first-time alert, and only that distinguishes a climber declining the alert - an explicit no -
/// from a request a standing denial refused before anyone was asked anything.
enum ClimbDropNotificationIntentPolicy {
    static func decision(
        initialStatus: UNAuthorizationStatus,
        resolvedStatus: UNAuthorizationStatus
    ) -> ClimbDropNotificationIntentDecision {
        switch initialStatus {
        case .notDetermined:
            guard resolvedStatus != .notDetermined else { return .preserve }
            return .record(resolvedStatus.allowsRemoteUserVisibleNotifications)
        case .denied:
            return .preserve
        case .authorized, .provisional, .ephemeral:
            return .record(true)
        @unknown default:
            return .preserve
        }
    }
}
