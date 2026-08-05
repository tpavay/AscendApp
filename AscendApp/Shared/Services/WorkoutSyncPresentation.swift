import Foundation

/// What the inline sync row shows for one workout.
///
/// Derived from whether the climb is in the cloud, never from what the retry machinery is doing.
/// Gating on the machinery - `status == .rejected`, or a view-local in-flight flag - is what made
/// the warning vanish the instant a climber tapped retry, and vanish again when that retry was
/// refused.
///
/// `Synced` is the only case that disappears, because it is a confirmation rather than a warning.
enum WorkoutSyncPresentation: Equatable, Sendable {
    /// In the cloud, and the climber was never told otherwise. No row.
    case hidden

    /// Not in the cloud yet, quietly. Neutral, no control - the automatic series is still working
    /// and there is nothing for the climber to do.
    case syncing

    /// Not in the cloud, and the climber needs to know. Amber, with `TRY AGAIN`.
    case couldNotSync

    /// The same warning, with the control dead because the device is offline.
    case couldNotSyncOffline

    /// The same warning, with the control showing `SYNCING` while a tap is in flight.
    ///
    /// The row text deliberately does not change here. A retry that is running has not made the
    /// climb any safer, so the statement about safety stays exactly as it was.
    case couldNotSyncRetrying

    /// Landed, for a climber who saw the warning first. Transient - this is the one that goes away.
    case synced

    var isWarning: Bool {
        switch self {
        case .couldNotSync, .couldNotSyncOffline, .couldNotSyncRetrying:
            return true
        case .hidden, .syncing, .synced:
            return false
        }
    }

    var showsRetryControl: Bool {
        isWarning
    }

    var isRetryControlEnabled: Bool {
        self == .couldNotSync
    }
}
