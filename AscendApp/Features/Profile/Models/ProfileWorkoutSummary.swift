import Foundation

struct ProfileWorkoutSummary: Identifiable, Equatable {
    let id: String
    let name: String
    let startedAt: Date
    let durationSeconds: TimeInterval
    let steps: Int
    let source: WorkoutSource
    let climbId: String?
    let climbTier: ClimbTier?
    let climbCompletionStatus: ClimbAttemptStatus?
    let climbCompletionDurationSeconds: Int?

    var isLiveClimb: Bool {
        source == .headphoneMotion || climbId != nil
    }

    var isCompletedClimb: Bool {
        climbCompletionStatus == .completed
    }

    var comparisonDurationSeconds: TimeInterval? {
        guard isCompletedClimb else { return nil }
        if let climbCompletionDurationSeconds, climbCompletionDurationSeconds > 0 {
            return TimeInterval(climbCompletionDurationSeconds)
        }
        return durationSeconds > 0 ? durationSeconds : nil
    }
}
