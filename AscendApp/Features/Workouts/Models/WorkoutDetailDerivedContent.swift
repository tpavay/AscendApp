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

        // The cheap predicates gate the expensive rebuild, not the other way round:
        // a session that renders no splits section must not pay for a checkpoint
        // curve nobody reads.
        guard let metadata,
              workout.isInAppSensorWorkout,
              Self.hasRecordedPaceSplitData(metadata: metadata, finalSteps: workout.steps) else {
            paceSplits = []
            showsPaceSplits = false
            return
        }

        let targetSteps = LiveClimbWorkoutSummaryData.summaryTargetSteps(metadata: metadata, workout: workout)
        let splits = LiveClimbWorkoutSummaryData.paceSplits(for: workout, targetSteps: targetSteps)
        paceSplits = splits
        showsPaceSplits = splits.count > 1
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
