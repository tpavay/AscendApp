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

    /// The step target a workout's metadata records, resolved the way the replay Cloud Function
    /// resolves it (`climbTargetStepCount` first, then `targetStepCount`). Metadata written before
    /// the target was recorded carries neither.
    static func targetStepCount(for metadata: HeadphoneMotionWorkoutMetadata) -> Int? {
        metadata.climbTargetStepCount ?? metadata.targetStepCount
    }

    /// The steps to record on an attempt. A climb stops counting at its target, so an attempt's
    /// recorded steps must not depend on which reader built it - saving and rehydrating the same
    /// session have to land on the same number.
    static func recordedSteps(steps: Int, targetStepCount: Int?) -> Int {
        guard let targetStepCount, targetStepCount > 0 else { return steps }
        return min(targetStepCount, steps)
    }

    /// The stop reason to persist alongside a saved live climb workout.
    ///
    /// Only a manual stop is upgraded: a user who tapped End past the target reached it, the
    /// auto-finish just did not fire first. Every other reason is left exactly as recorded.
    /// `.interrupted` in particular must never be upgraded - a recovered draft's step count is
    /// typed by hand in a free-entry field, and the replay Cloud Function gates publication on
    /// this value, so upgrading it would let a typed number claim a First Ascent, which is
    /// permanent and can never be reclaimed. Recovered drafts past the target still count
    /// locally: `attemptStatus` reads steps, never this reason.
    static func resolvedStopReason(
        _ stopReason: HeadphoneMotionSessionStopReason,
        steps: Int,
        targetStepCount: Int
    ) -> HeadphoneMotionSessionStopReason {
        guard stopReason == .userStopped else { return stopReason }
        return isCompletion(steps: steps, targetStepCount: targetStepCount) ? .targetReached : stopReason
    }

    /// Resolves the status of an attempt reconstructed from a workout's stored metadata.
    ///
    /// Metadata written before the target was recorded carries no step target, so those workouts
    /// fall back to the reason the session ended.
    static func attemptStatus(
        for metadata: HeadphoneMotionWorkoutMetadata,
        steps: Int
    ) -> ClimbAttemptStatus {
        guard let targetStepCount = targetStepCount(for: metadata) else {
            return metadata.stopReason == .targetReached ? .completed : .failed
        }

        return attemptStatus(steps: steps, targetStepCount: targetStepCount)
    }
}
