import UserNotifications

/// What an enable request means for the stored climb-drop preference.
enum ClimbDropNotificationIntentDecision: Equatable {
    /// The climber answered, and this is the answer to store.
    case record(Bool)
    /// Nothing new was chosen, so the stored intent stands.
    case preserve
}

/// Reads an enable request's outcome as the climber's intent, and says where the request leaves
/// them.
///
/// Only the authorization status the request started from says whether iOS presented its
/// first-time alert. That is the whole difference between a climber declining the alert - an
/// explicit no, recorded as one - and a climber asking again while a denial from some earlier day
/// still stands, which is a fresh yes that iOS was never given the chance to answer.
enum ClimbDropNotificationIntentPolicy {
    static func decision(
        initialStatus: UNAuthorizationStatus,
        resolvedStatus: UNAuthorizationStatus
    ) -> ClimbDropNotificationIntentDecision {
        switch initialStatus {
        case .notDetermined:
            guard resolvedStatus != .notDetermined else { return .preserve }
            return .record(resolvedStatus.allowsRemoteUserVisibleNotifications)
        case .denied, .authorized, .provisional, .ephemeral:
            return .record(true)
        @unknown default:
            return .preserve
        }
    }

    /// True when iOS Settings is the only place left that can act on the answer just recorded.
    /// A climber who declined the alert this moment is not marched anywhere over it.
    static func routesToSystemSettings(
        initialStatus: UNAuthorizationStatus,
        resolvedStatus: UNAuthorizationStatus
    ) -> Bool {
        initialStatus == .denied && resolvedStatus == .denied
    }
}
