import Foundation

enum WorkoutSyncError: LocalizedError {
    case notAuthenticated
    case missingOwner
    case unsupportedSource(String)
    case invalidHeartRateSeries

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to sync workouts."
        case .missingOwner:
            return "Workout sync requires an owning user."
        case .unsupportedSource(let source):
            return "Workout sync does not support source '\(source)' yet."
        case .invalidHeartRateSeries:
            return "Heart-rate samples must include at least one entry."
        }
    }
}
