import Foundation

enum WorkoutHeartRateRestoreStatus: String, Codable, Sendable {
    case notNeeded = "not_needed"
    case pending
    case ready
    case retryPending = "retry_pending"
    case unavailable

    /// Whether an empty local heart-rate series means the workout genuinely has none, as opposed to
    /// a durable sidecar this device has not restored yet.
    var treatsLocalAbsenceAsAuthoritative: Bool {
        switch self {
        case .notNeeded, .ready:
            true
        case .pending, .retryPending, .unavailable:
            false
        }
    }

    var awaitsRemoteRestore: Bool {
        switch self {
        case .pending, .retryPending:
            true
        case .notNeeded, .ready, .unavailable:
            false
        }
    }
}
