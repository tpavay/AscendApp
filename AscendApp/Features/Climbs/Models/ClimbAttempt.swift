import Foundation
import SwiftData

@Model
final class ClimbAttempt {
    var id: UUID = UUID()
    var climbId: String = ""
    var statusRawValue: String = ClimbAttemptStatus.active.rawValue
    var startedAt: Date = Date()
    var endedAt: Date? = nil
    var completedAt: Date? = nil
    var accumulatedSteps: Int = 0
    var accumulatedDurationSeconds: Int = 0
    var sessionsCount: Int = 0
    var appliedWorkoutIdsData: Data? = nil
    var bestCompletionDurationSeconds: Int? = nil
    var completedInSingleSessionMulti: Bool = false

    var status: ClimbAttemptStatus {
        get { ClimbAttemptStatus(rawValue: statusRawValue) ?? .active }
        set { statusRawValue = newValue.rawValue }
    }

    var appliedWorkoutIds: [String] {
        get {
            guard let appliedWorkoutIdsData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: appliedWorkoutIdsData)) ?? []
        }
        set {
            appliedWorkoutIdsData = try? JSONEncoder().encode(newValue)
        }
    }

    init(
        climbId: String,
        status: ClimbAttemptStatus = .active,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        completedAt: Date? = nil,
        accumulatedSteps: Int = 0,
        accumulatedDurationSeconds: Int = 0,
        sessionsCount: Int = 0,
        appliedWorkoutIds: [String] = [],
        bestCompletionDurationSeconds: Int? = nil,
        completedInSingleSessionMulti: Bool = false
    ) {
        self.id = UUID()
        self.climbId = climbId
        self.statusRawValue = status.rawValue
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.completedAt = completedAt
        self.accumulatedSteps = accumulatedSteps
        self.accumulatedDurationSeconds = accumulatedDurationSeconds
        self.sessionsCount = sessionsCount
        self.appliedWorkoutIds = appliedWorkoutIds
        self.bestCompletionDurationSeconds = bestCompletionDurationSeconds
        self.completedInSingleSessionMulti = completedInSingleSessionMulti
    }
}
