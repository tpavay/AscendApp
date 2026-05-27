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

    var isLiveClimb: Bool {
        source == .headphoneMotion || climbId != nil
    }
}
