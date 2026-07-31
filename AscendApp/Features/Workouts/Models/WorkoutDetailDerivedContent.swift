import Foundation

/// The activity detail screen's expensive derivations, resolved once per render
/// pass instead of once per reader.
///
/// The screen used to reach for each of these from several computed properties
/// inside a single body evaluation: the headphone-motion metadata was JSON-decoded
/// seven times, the pace splits were rebuilt twice (each rebuild decoding the
/// metadata again), and the stored heart-rate blob - 104 KB for a 43-minute
/// session - was decoded three times, about 13 ms of duplicated work per pass on
/// a screen whose frame budget is 8 ms.
struct WorkoutDetailDerivedContent {
    let liveClimbMetadata: HeadphoneMotionWorkoutMetadata?
    let heartRateSeries: [HeartRateDataPoint]
    let paceSplits: [LiveClimbPaceSplit]
    let showsPaceSplits: Bool

    init(workout: Workout) {
        let metadata = LiveClimbWorkoutSummaryData.metadata(for: workout)
        liveClimbMetadata = metadata
        heartRateSeries = workout.heartRateTimeSeries

        guard let metadata else {
            paceSplits = []
            showsPaceSplits = false
            return
        }

        let targetSteps = max(metadata.targetStepCount ?? workout.steps, workout.steps, 1)
        let splits = LiveClimbWorkoutSummaryData.paceSplits(for: workout, targetSteps: targetSteps)
        paceSplits = splits
        showsPaceSplits = workout.isInAppSensorWorkout &&
            splits.count > 1 &&
            Self.hasRecordedPaceSplitData(metadata: metadata, finalSteps: workout.steps)
    }

    var canOpenLiveClimbSummary: Bool {
        liveClimbMetadata != nil
    }

    /// A session only earns a splits section when the recorder actually captured
    /// intermediate checkpoints; otherwise the "splits" would be a straight line
    /// reconstructed from the final total.
    private static func hasRecordedPaceSplitData(
        metadata: HeadphoneMotionWorkoutMetadata,
        finalSteps: Int
    ) -> Bool {
        guard let intervalSeconds = metadata.splitIntervalSeconds,
              intervalSeconds > 0,
              let splitSteps = metadata.splitSteps,
              splitSteps.count > 2 else {
            return false
        }

        let resolvedFinalSteps = max(finalSteps, 0)
        return splitSteps.dropLast().contains { step in
            step > 0 && step < resolvedFinalSteps
        }
    }
}
