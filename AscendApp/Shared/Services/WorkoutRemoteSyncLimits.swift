import Foundation

/// The limits a backed-up workout document must satisfy, stated once on the writing side.
///
/// These mirror `firestore.rules` deliberately and by hand, because rules cannot import Swift.
/// The point is that they agree: the rule used to declare eight participations, could actually
/// evaluate one, and the client emitted however many the workout had. The effective ceiling
/// therefore moved depending on which *other* optional fields happened to be present, and a
/// workout that crossed it got a bare `PERMISSION_DENIED` that was indistinguishable from a
/// deliberate refusal (ASCEND-IOS-1J).
///
/// Changing a number here means changing `firestore.rules` and re-running
/// `tests/firebase-rules/workout-expression-budget.test.mjs` in the same change. A limit the
/// client will exceed is a workout the server refuses forever.
///
/// This is not the whole set of bounds the rule declares, and it is not meant to be. The physical
/// envelope on `steps`, `durationSeconds` and `startedAt` (`isPhysicallyPossibleClimb` in
/// `firestore.rules`, which owns the numbers and the reasoning) is deliberately not mirrored here:
/// `WorkoutPlausibilityPolicy` already refuses a tighter cadence than the rule's on the way into
/// `WorkoutRemoteSyncMapper.snapshot`, and the duration ceiling is bounded at the one place that
/// could reach it, `ActiveHeadphoneWorkoutDraftStore.maximumCreditableTrackingGap`. Mirror a bound
/// here only when nothing upstream already makes it unreachable.
enum WorkoutRemoteSyncLimits {
    /// Matches `maxWorkoutParticipations()` in `firestore.rules`.
    ///
    /// Four is what the rule can evaluate alongside a fully-populated document, measured against
    /// the emulator rather than assumed. Nothing in the app can currently produce more than one:
    /// `WorkoutParticipationService` has a routine producer and a climb-attempt producer, and
    /// every path that creates a workout runs one or the other, never both.
    static let maximumParticipations = 4
}
