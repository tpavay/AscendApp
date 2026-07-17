import Foundation

/// The single definition of what finishing a Live Climb means.
///
/// Three readers need this answer and must never disagree: the client deciding an attempt's
/// status at save time, the client rehydrating attempts from remote backups after a reinstall,
/// and the Cloud Function that publishes replay leaderboard rows. When they disagreed, a user
/// who tapped End right after passing the step target kept the climb locally but lost it on
/// reinstall.
///
/// Reaching the step target is the finish. `stopReason` records *how* a session ended, not
/// whether it counted, so it can never be the primary signal.
enum LiveClimbCompletionPolicy {
    static func isCompletion(steps: Int, targetStepCount: Int?) -> Bool {
        guard let targetStepCount, targetStepCount > 0 else { return false }
        return steps >= targetStepCount
    }

    static func attemptStatus(steps: Int, targetStepCount: Int) -> ClimbAttemptStatus {
        isCompletion(steps: steps, targetStepCount: targetStepCount) ? .completed : .failed
    }

    /// The stop reason to persist alongside a saved live climb workout.
    ///
    /// A session that passed the target reached it, whether the auto-finish fired or the user
    /// tapped End first. Normalizing here keeps the stored metadata true for every later reader,
    /// including the replay Cloud Function, which additionally gates publication on this value.
    static func resolvedStopReason(
        _ stopReason: HeadphoneMotionSessionStopReason,
        steps: Int,
        targetStepCount: Int
    ) -> HeadphoneMotionSessionStopReason {
        isCompletion(steps: steps, targetStepCount: targetStepCount) ? .targetReached : stopReason
    }

    /// Resolves the status of an attempt reconstructed from a workout's stored metadata.
    ///
    /// Mirrors the Cloud Function's target resolution (`climbTargetStepCount` first, then
    /// `targetStepCount`). Metadata written before the target was recorded carries no step
    /// target, so those workouts fall back to the reason the session ended.
    static func attemptStatus(
        for metadata: HeadphoneMotionWorkoutMetadata,
        steps: Int
    ) -> ClimbAttemptStatus {
        guard let targetStepCount = metadata.climbTargetStepCount ?? metadata.targetStepCount else {
            return metadata.stopReason == .targetReached ? .completed : .failed
        }

        return attemptStatus(steps: steps, targetStepCount: targetStepCount)
    }
}
