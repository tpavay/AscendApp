import CryptoKit
import Foundation

/// The single definition of "a legacy completion we trust enough to recover".
///
/// The same four conditions gate three places: this hydration guard input (Swift), the replay
/// publication fallback (`functions/src/legacyClimbCompletion.ts`), and the eventual Phase 3
/// migration. Copying the conditions into each site guarantees drift, so they live here once and
/// are mirrored per language, pinned by the shared vector at
/// `SharedTestVectors/legacy-recoverable-completion-vector.json`.
///
/// A legacy completion is recoverable iff it is a headphone-motion capture, names a landmark
/// (non-empty `climbId`), and finished by the completion policy's own rule: `steps >= target` when
/// a step target was recorded, otherwise `stopReason == target_reached`. This is deliberately the
/// same "finish" definition `LiveClimbCompletionPolicy` uses, applied to the resolved metadata.
enum LegacyClimbCompletionPredicate {
    /// The pure contract, evaluated on already-resolved fields so Swift and TypeScript share one
    /// test vector. `targetStepCount` is the resolved metadata target (`climbTargetStepCount ??
    /// targetStepCount`), or `nil` when the backup predates recording a target.
    static func isRecoverableLegacyCompletion(
        source: String,
        climbId: String?,
        stopReason: String,
        steps: Int,
        targetStepCount: Int?
    ) -> Bool {
        guard source == HeadphoneMotionWorkoutMetadata.headphoneMotionSource else { return false }
        guard let climbId, !climbId.isEmpty else { return false }

        if let targetStepCount, targetStepCount > 0 {
            return steps >= targetStepCount
        }
        return stopReason == HeadphoneMotionSessionStopReason.targetReached.rawValue
    }

    /// Convenience over a restored workout: reads the headphone-motion metadata and evaluates the
    /// contract. Non-headphone or unreadable-metadata workouts are never recoverable completions.
    static func isRecoverableLegacyCompletion(workout: Workout) -> Bool {
        guard let metadata = LiveClimbWorkoutSummaryData.metadata(for: workout) else { return false }
        return isRecoverableLegacyCompletion(
            source: metadata.source,
            climbId: metadata.climbId,
            stopReason: metadata.stopReason.rawValue,
            steps: workout.steps,
            targetStepCount: LiveClimbCompletionPolicy.targetStepCount(for: metadata)
        )
    }

    /// The deterministic attempt id used when no participation supplies one (CANONICAL §8). It is a
    /// stable UUIDv5-style hash of `uid + legacyWorkoutId + landmarkId`, so rehydrating the same
    /// backup on any device - or re-running the Phase 3 migration - lands on the same attempt and
    /// never duplicates (serves invariant I2). The Phase 3 migration reuses this exact form.
    static func deterministicAttemptId(
        userId: String,
        legacyWorkoutId: UUID,
        climbId: String
    ) -> UUID {
        let seed = "\(userId)|\(legacyWorkoutId.uuidString)|\(climbId)"
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
