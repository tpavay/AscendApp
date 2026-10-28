import Foundation

/// Splits for the share sheet, read from the workout's recorded progress curve.
///
/// A climb that was never split, or whose curve the pre-fix sampler stopped at the hour, has no
/// splits here: a card has no room to say which rows were never measured, so it does not get the
/// split layouts or stickers at all. The split length is the app's own rule,
/// `LiveClimbWorkoutSummaryData.paceSplitDurationSeconds`.
enum ShareSheetSplitResolver {
    static func resolve(for workout: Workout) -> [ShareSheetSubject.Split] {
        guard let metadata = LiveClimbWorkoutSummaryData.metadata(for: workout),
              let intervalSeconds = metadata.splitIntervalSeconds,
              intervalSeconds > 0,
              let splitSteps = metadata.splitSteps,
              splitSteps.count >= 2,
              splitSteps.contains(where: { $0 > 0 }) else {
            return []
        }

        let targetSteps = max(
            metadata.climbTargetStepCount ?? metadata.targetStepCount ?? workout.steps,
            workout.steps,
            1
        )
        let splits = LiveClimbWorkoutSummaryData.paceSplits(for: workout, targetSteps: targetSteps)
        guard splits.count >= 2, splits.allSatisfy(\.isMeasured) else { return [] }

        return splits.map { split in
            ShareSheetSubject.Split(
                index: split.index,
                durationSeconds: max(split.endElapsedSeconds - split.startElapsedSeconds, 1),
                steps: split.steps,
                stepsPerMinute: split.stepsPerMinute
            )
        }
    }
}
