import Foundation
import SwiftData

/// The persisted retry schedule for one workout that is not yet in the cloud.
///
/// Deliberately a separate model rather than more columns on `Workout`. `Workout`'s relationships
/// mean freezing its shape would force frozen copies of `WorkoutSourceLink` and
/// `WorkoutParticipation` across two already-shipped schema versions, and a migration that goes
/// wrong on a real device cannot be rolled back. A brand-new model has no rows to default, changes
/// no existing shape, and keeps the stage genuinely lightweight - the same reasoning that made
/// `PendingWorkoutDeletion` and `PendingRoutineDeletion` their own models.
///
/// This holds the *schedule*, never the verdict. `Workout.remoteSyncStatus` remains the single
/// status the UI reads, so there is still exactly one answer to "is this climb in the cloud" and
/// the two can never disagree.
///
/// `nextEligibleAttemptAt` is why this is persisted at all. An attempt count on its own can be
/// consumed by three coordinator triggers in the same millisecond - seven surfaces call the
/// coordinator, and a re-entrant call re-runs the pending query - so the gate has to be a clock,
/// and the clock has to survive relaunch or every launch becomes a loophole around the policy.
@Model
final class WorkoutSyncOutboxEntry {
    var workoutId: UUID = UUID()
    var ownerUserId: String = ""

    /// No-earlier-than time for the next automatic attempt. Nil means "due now".
    var nextEligibleAttemptAt: Date?

    /// When the cloud first had something of this workout's it had not acknowledged. Anchors both
    /// the 30-minute attention threshold and the elapsed arm of the refusal stop.
    var firstPendingAt: Date?

    /// When the cloud last saw this workout. Doubles as the payload revision the schedule is armed
    /// against - see ``isScheduledForPayloadRevision(at:)``.
    var lastAttemptAt: Date?

    /// Genuine remote outcomes only. Offline deferral and lifecycle cancellation never count -
    /// charging a teardown as evidence is what turned one stuck workout into 499 events.
    var automaticAttemptCount: Int = 0
    var refusalCount: Int = 0

    var failureCategoryRawValue: String?

    init(
        workoutId: UUID,
        ownerUserId: String,
        firstPendingAt: Date? = nil
    ) {
        self.workoutId = workoutId
        self.ownerUserId = ownerUserId
        self.firstPendingAt = firstPendingAt
    }

    var failureCategory: WorkoutSyncFailureCategory? {
        get { failureCategoryRawValue.flatMap(WorkoutSyncFailureCategory.init(rawValue:)) }
        set { failureCategoryRawValue = newValue?.rawValue }
    }

    /// Records a genuine remote outcome and arms the next due date.
    func recordFailure(
        category: WorkoutSyncFailureCategory,
        now: Date,
        randomFraction: Double = Double.random(in: 0...1)
    ) {
        failureCategory = category
        lastAttemptAt = now
        if firstPendingAt == nil { firstPendingAt = now }

        // Offline and cancellation leave the schedule exactly where it was. They are not evidence,
        // so they neither advance the series nor push out the next due attempt.
        guard category.consumesAttempt else { return }

        automaticAttemptCount += 1
        if category == .refused { refusalCount += 1 }

        nextEligibleAttemptAt = WorkoutSyncRetryPolicy.nextEligibleAttemptDate(
            afterAttemptCount: automaticAttemptCount,
            from: now,
            randomFraction: randomFraction
        )
    }

    /// Whether the automatic series is over. Every arm is conjunctive with elapsed time, so a burst
    /// of triggers cannot retire a workout early.
    func hasStoppedAutomaticAttempts(now: Date) -> Bool {
        if failureCategory?.requiresImmediateAttention == true { return true }

        if WorkoutSyncRetryPolicy.refusalsHaveEarnedStop(
            refusalCount: refusalCount,
            firstPendingAt: firstPendingAt,
            now: now
        ) {
            return true
        }

        return WorkoutSyncRetryPolicy.hasExhaustedAutomaticAttempts(
            attemptCount: automaticAttemptCount,
            firstPendingAt: firstPendingAt,
            now: now
        )
    }

    /// Whether an automatic pass may attempt this workout now.
    func isDueForAutomaticAttempt(now: Date) -> Bool {
        guard !hasStoppedAutomaticAttempts(now: now) else { return false }
        guard let nextEligibleAttemptAt else { return true }

        return now >= WorkoutSyncRetryPolicy.clampedEligibilityDate(nextEligibleAttemptAt, now: now)
    }

    /// Whether the climber should be told, rather than left with the quiet waiting state.
    func requiresAttention(now: Date) -> Bool {
        if hasStoppedAutomaticAttempts(now: now) { return true }

        return WorkoutSyncRetryPolicy.requiresAttention(
            category: failureCategory,
            firstPendingAt: firstPendingAt,
            now: now
        )
    }

    /// Re-opens exactly one automatic attempt after the basis for the stop has moved: a new build,
    /// an operator-bumped recovery epoch, repaired authentication, or connectivity returning when
    /// offline was the recorded blocker.
    ///
    /// Screen appearance, tab switches and repeated coordinator calls deliberately do not qualify.
    func reopenOneAutomaticAttempt(now: Date) {
        nextEligibleAttemptAt = now
        automaticAttemptCount = max(automaticAttemptCount - 1, 0)
        refusalCount = 0
        failureCategory = nil
    }

    /// Whether this schedule was armed against the bytes the workout is offering now.
    ///
    /// `lastAttemptAt` is the moment the cloud last saw this workout, and every path that gives it
    /// something new to offer - a local edit, a photo finishing its upload, a participation being
    /// attached - goes through `Workout.markPendingRemoteUpsert`, which moves `lastModifiedAt`. So
    /// a workout modified since its last attempt is offering different bytes from the ones this
    /// series was refused for, and holding it to that verdict is what left an edited stopped
    /// workout neither retried nor visible.
    ///
    /// An entry the cloud has never seen has nothing to be stale against, and no schedule to lose.
    func isScheduledForPayloadRevision(at revisionAt: Date) -> Bool {
        guard let lastAttemptAt else { return true }
        return revisionAt <= lastAttemptAt
    }

    /// A local edit is a new payload revision, so the series starts over.
    ///
    /// Manual retry deliberately does not come through here: it re-offers the same bytes and must
    /// not reset the schedule it is bypassing for one attempt.
    func resetForNewPayloadRevision(now: Date) {
        nextEligibleAttemptAt = nil
        firstPendingAt = now
        lastAttemptAt = nil
        automaticAttemptCount = 0
        refusalCount = 0
        failureCategory = nil
    }
}
