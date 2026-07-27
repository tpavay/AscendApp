import Foundation

enum WorkoutHeartRateRestoreStatus: String, Codable, Sendable {
    case notNeeded = "not_needed"
    case pending
    case ready
    case retryPending = "retry_pending"
    case unavailable
}
