import Foundation

struct ClimbHistoryEntry: Identifiable, Equatable {
    let attemptId: UUID
    let status: ClimbAttemptStatus
    let date: Date
    let durationSeconds: Int
    let recordedSteps: Int
    let totalSteps: Int
    let isPersonalBest: Bool

    var id: UUID { attemptId }
}
