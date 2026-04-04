import Foundation

struct ActiveClimbSummary: Identifiable, Equatable {
    let attemptId: UUID
    let climb: Climb
    let accumulatedSteps: Int
    let requiredSteps: Int
    let accumulatedDurationSeconds: Int
    let sessionsCount: Int
    let startedAt: Date
    let projectedCollectionOrder: Int

    var id: UUID { attemptId }

    var remainingSteps: Int {
        max(requiredSteps - accumulatedSteps, 0)
    }

    var progressFraction: Double {
        guard requiredSteps > 0 else { return 0 }
        return min(max(Double(accumulatedSteps) / Double(requiredSteps), 0), 1)
    }

    var progressPercent: Int {
        Int((progressFraction * 100).rounded())
    }

    var progressText: String {
        "\(accumulatedSteps.formatted()) / \(requiredSteps.formatted())"
    }
}
