import Foundation
import SwiftData

@MainActor
struct WorkoutDerivedDataService {
    static func recalculateAll(
        modelContext: ModelContext,
        settingsManager: SettingsManager = .shared
    ) throws {
        let workoutDescriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let allWorkouts = try modelContext.fetch(workoutDescriptor)

        let baselineResult = UserBaselineService.calculateBaseline(
            from: allWorkouts,
            seededLevel: settingsManager.seededBaseLevel
        )
        settingsManager.updateAutoCalculatedBaseLevel(baselineResult?.autoCalibratedLevel)

        for workout in allWorkouts {
            let analysis = WorkoutEffortService.analyze(
                workout: workout,
                baseLevel: settingsManager.effectiveBaseLevel
            )
            workout.equivalentLevel = analysis.equivalentLevel
            workout.effortScoreValue = analysis.score
        }

        for workout in allWorkouts {
            workout.percentileScores = PercentileScoreService.calculateAllPercentiles(
                for: workout,
                existingWorkouts: allWorkouts,
                preferredMetric: settingsManager.preferredWorkoutMetric
            )
        }

        try PersonalRecordService.recalculateAllPersonalRecords(
            modelContext: modelContext,
            measurementSystem: settingsManager.measurementSystem,
            stepHeight: settingsManager.stepHeight
        )

        try modelContext.save()
        try RoutineService(modelContext: modelContext).ensureBuiltInRoutinesExist()
        NotificationCenter.default.post(name: .routineTemplatesDidChange, object: nil)
    }
}
