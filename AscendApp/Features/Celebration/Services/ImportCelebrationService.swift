//
//  ImportCelebrationService.swift
//  AscendApp
//

import Foundation
import SwiftData

@MainActor
struct ImportCelebrationService {
    typealias CapturedGoal = (goal: Goal, progress: GoalProgress)

    static func fetchAllWorkouts(modelContext: ModelContext) throws -> [Workout] {
        let descriptor = FetchDescriptor<Workout>()
        return try modelContext.fetch(descriptor)
    }

    static func captureGoalSnapshot(
        modelContext: ModelContext,
        existingWorkouts: [Workout],
        referenceDate: Date = Date()
    ) -> CapturedGoal? {
        do {
            let goalService = GoalService(modelContext: modelContext)
            guard let goal = try goalService.getActiveGoal() else { return nil }
            let progress = GoalProgressService.calculateProgress(
                for: goal,
                from: existingWorkouts,
                at: referenceDate
            )
            return (goal: goal, progress: progress)
        } catch {
            return nil
        }
    }

    static func buildGoalData(
        preGoal: Goal,
        preProgress: GoalProgress,
        allWorkoutsAfterImport: [Workout],
        referenceDate: Date
    ) -> GoalCelebrationSnapshot {
        let postProgress = GoalProgressService.calculateProgress(
            for: preGoal,
            from: allWorkoutsAfterImport,
            at: referenceDate
        )

        return GoalCelebrationSnapshot(
            goalId: preGoal.id,
            metric: preGoal.metric,
            target: preGoal.target,
            previousPercent: preProgress.percent,
            newPercent: postProgress.percent,
            previousCurrent: preProgress.current,
            newCurrent: postProgress.current,
            goalCompleted: preProgress.percent < 1.0 && postProgress.percent >= 1.0,
            formattedTarget: formattedTarget(for: preGoal)
        )
    }

    private static func formattedTarget(for goal: Goal) -> String {
        let unit = goal.target == 1 ? goal.metric.unitSingular : goal.metric.unit
        return "\(goal.target.formatted()) \(unit)"
    }
}
