import Foundation

enum WorkoutSyncError: LocalizedError {
    case notAuthenticated
    case missingOwner
    case unsupportedSource(String)
    case invalidHeartRateSeries
    case implausibleWorkoutTotals
    case tooManyParticipations(count: Int)

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
        case .implausibleWorkoutTotals:
            return "Workout totals are outside the supported range."
        case .tooManyParticipations(let count):
            return """
            This workout is linked to \(count) contexts, more than the \
            \(WorkoutRemoteSyncLimits.maximumParticipations) cloud backup supports.
            """
        }
    }
}
