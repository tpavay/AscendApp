import FirebaseFirestore
import Foundation
import Testing
@testable import AscendApp

/// The policy that replaced a count-only threshold.
///
/// The defect these exist for: three coordinator triggers landing in the same millisecond consumed
/// the entire retry budget, so a threshold meant to survive a transient rules-deploy window was
/// gone before the window closed.
struct WorkoutSyncRetryPolicyTests {
    private let start = Date(timeIntervalSince1970: 1_780_000_000)

    @Test
    func theScheduleIsCoarseAndSpacedInRealTime() {
        // Deliberately far coarser than Firestore's own 1s-to-60s transport backoff: this layer
        // decides when to re-offer a logical backup, not when to retransmit a packet.
        #expect(WorkoutSyncRetryPolicy.attemptOffsets == [0, 60, 300, 900, 3600, 21_600, 86_400])
    }

    @Test
    func jitterOnlyEverPushesAnAttemptLater() {
        // Downward jitter would let an attempt land before its own due time, which is the single
        // guarantee the persisted date exists to make.
        for fraction in [0.0, 0.5, 1.0] {
            let due = try! #require(
                WorkoutSyncRetryPolicy.nextEligibleAttemptDate(
                    afterAttemptCount: 1,
                    from: start,
                    randomFraction: fraction
                )
            )
            #expect(due >= start.addingTimeInterval(60))
            #expect(due <= start.addingTimeInterval(60 * 1.2))
        }
    }

    @Test
    func theSeriesEndsOnlyWhenBothTheCountAndTheClockAgree() {
        // Seven attempts alone is not enough; the 24-hour offset has to have elapsed too, so a
        // burst cannot retire a workout early.
        #expect(
            WorkoutSyncRetryPolicy.hasExhaustedAutomaticAttempts(
                attemptCount: 7,
                firstPendingAt: start,
                now: start.addingTimeInterval(60)
            ) == false
        )
        #expect(
            WorkoutSyncRetryPolicy.hasExhaustedAutomaticAttempts(
                attemptCount: 7,
                firstPendingAt: start,
                now: start.addingTimeInterval(86_400)
            )
        )
    }

    /// The conjunctive gate the captain asked for, and the reason `permissionDenied` is not called
    /// permanent: a deployable rules defect produces the same code as a genuine denial.
    @Test
    func threeRefusalsInOneMillisecondCannotStopTheSeries() {
        #expect(
            WorkoutSyncRetryPolicy.refusalsHaveEarnedStop(
                refusalCount: 3,
                firstPendingAt: start,
                now: start
            ) == false
        )
        #expect(
            WorkoutSyncRetryPolicy.refusalsHaveEarnedStop(
                refusalCount: 3,
                firstPendingAt: start,
                now: start.addingTimeInterval(29 * 60)
            ) == false
        )
        #expect(
            WorkoutSyncRetryPolicy.refusalsHaveEarnedStop(
                refusalCount: 3,
                firstPendingAt: start,
                now: start.addingTimeInterval(30 * 60)
            )
        )
    }

    @Test
    func elapsedTimeAloneDoesNotStopTheSeriesEither() {
        #expect(
            WorkoutSyncRetryPolicy.refusalsHaveEarnedStop(
                refusalCount: 2,
                firstPendingAt: start,
                now: start.addingTimeInterval(24 * 60 * 60)
            ) == false
        )
    }

    @Test
    func attentionArrivesAfterThirtyQuietMinutes() {
        #expect(
            WorkoutSyncRetryPolicy.requiresAttention(
                category: .transient,
                firstPendingAt: start,
                now: start.addingTimeInterval(29 * 60)
            ) == false
        )
        #expect(
            WorkoutSyncRetryPolicy.requiresAttention(
                category: .transient,
                firstPendingAt: start,
                now: start.addingTimeInterval(30 * 60)
            )
        )
    }

    @Test
    func aMalformedRequestIsSurfacedImmediately() {
        // Nothing about waiting can make an unacceptable request acceptable.
        #expect(
            WorkoutSyncRetryPolicy.requiresAttention(
                category: .malformed,
                firstPendingAt: start,
                now: start
            )
        )
    }

    @Test
    func aClockMovedBackwardCannotParkAWorkoutForever() {
        let farFuture = start.addingTimeInterval(400 * 24 * 60 * 60)
        let clamped = WorkoutSyncRetryPolicy.clampedEligibilityDate(farFuture, now: start)

        #expect(clamped <= start.addingTimeInterval(86_400 * 1.2))
    }

    @Test
    func aClockMovedForwardCannotMakeEveryDeadlineFallDueAtOnce() {
        let stale = start.addingTimeInterval(-400 * 24 * 60 * 60)

        #expect(WorkoutSyncRetryPolicy.clampedEligibilityDate(stale, now: start) == start)
    }

    @Test
    func offlineAndCancellationAreNotEvidenceAndConsumeNoAttempt() {
        #expect(WorkoutSyncFailureCategory.cancelled.consumesAttempt == false)
        #expect(WorkoutSyncFailureCategory.offline.consumesAttempt == false)
        #expect(WorkoutSyncFailureCategory.refused.consumesAttempt)
        #expect(WorkoutSyncFailureCategory.transient.consumesAttempt)
    }

    /// `permissionDenied` is `refused`, never `malformed`. It is terminal to the SDK but ambiguous
    /// to Ascend, so it earns the count-plus-elapsed gate rather than an instant verdict.
    @Test
    func permissionDeniedIsAmbiguousRatherThanMalformed() {
        let denied = NSError(
            domain: FirestoreErrorDomain,
            code: FirestoreErrorCode.permissionDenied.rawValue
        )

        #expect(WorkoutSyncFailureClassifier.category(for: denied, isConnected: true) == .refused)
        #expect(WorkoutSyncFailureCategory.refused.requiresImmediateAttention == false)
    }

    @Test
    func theClassifierMatchesThePinnedSDKsWriteClassification() {
        func category(_ code: Int) -> WorkoutSyncFailureCategory {
            WorkoutSyncFailureClassifier.category(
                for: NSError(domain: FirestoreErrorDomain, code: code),
                isConnected: true
            )
        }

        #expect(category(FirestoreErrorCode.invalidArgument.rawValue) == .malformed)
        #expect(category(FirestoreErrorCode.dataLoss.rawValue) == .malformed)
        #expect(category(FirestoreErrorCode.failedPrecondition.rawValue) == .refused)
        #expect(category(FirestoreErrorCode.unauthenticated.rawValue) == .authentication)
        #expect(category(FirestoreErrorCode.aborted.rawValue) == .transient)
        #expect(category(FirestoreErrorCode.resourceExhausted.rawValue) == .transient)
    }

    @Test
    func anUnreachableNetworkIsOfflineRatherThanAConsumedAttempt() {
        let unavailable = NSError(
            domain: FirestoreErrorDomain,
            code: FirestoreErrorCode.unavailable.rawValue
        )

        #expect(WorkoutSyncFailureClassifier.category(for: unavailable, isConnected: false) == .offline)
        #expect(WorkoutSyncFailureClassifier.category(for: unavailable, isConnected: true) == .transient)
    }

    @Test
    func aCancelledTaskIsNeverAVerdict() {
        #expect(WorkoutSyncFailureClassifier.category(for: CancellationError(), isConnected: true) == .cancelled)
        #expect(
            WorkoutSyncFailureClassifier.category(
                for: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled),
                isConnected: true
            ) == .cancelled
        )
    }
}

/// The persisted schedule itself - the half that has to survive relaunch.
struct WorkoutSyncOutboxEntryTests {
    private let start = Date(timeIntervalSince1970: 1_780_000_000)

    /// The exact defect the captain rejected: a burst of triggers consuming the whole budget.
    @Test
    func aBurstOfFailuresInOneInstantCannotConsumeTheSchedule() {
        let entry = WorkoutSyncOutboxEntry(workoutId: UUID(), ownerUserId: "user-123")

        entry.recordFailure(category: .refused, now: start, randomFraction: 0)
        #expect(entry.isDueForAutomaticAttempt(now: start) == false)

        // Every later trigger in the same instant is refused by the clock, not by a counter.
        for _ in 0..<10 {
            #expect(entry.isDueForAutomaticAttempt(now: start) == false)
        }
        #expect(entry.automaticAttemptCount == 1)
        #expect(entry.hasStoppedAutomaticAttempts(now: start) == false)
    }

    @Test
    func theNextAttemptBecomesDueOnlyAfterItsOwnOffsetElapses() {
        let entry = WorkoutSyncOutboxEntry(workoutId: UUID(), ownerUserId: "user-123")
        entry.recordFailure(category: .transient, now: start, randomFraction: 0)

        #expect(entry.isDueForAutomaticAttempt(now: start.addingTimeInterval(59)) == false)
        #expect(entry.isDueForAutomaticAttempt(now: start.addingTimeInterval(60)))
    }

    @Test
    func offlineLeavesTheScheduleExactlyWhereItWas() {
        let entry = WorkoutSyncOutboxEntry(workoutId: UUID(), ownerUserId: "user-123")
        entry.recordFailure(category: .offline, now: start)

        #expect(entry.automaticAttemptCount == 0)
        #expect(entry.nextEligibleAttemptAt == nil)
        #expect(entry.isDueForAutomaticAttempt(now: start))
    }

    @Test
    func cancellationLeavesTheScheduleExactlyWhereItWas() {
        let entry = WorkoutSyncOutboxEntry(workoutId: UUID(), ownerUserId: "user-123")
        entry.recordFailure(category: .transient, now: start, randomFraction: 0)
        let dueAfterGenuineFailure = entry.nextEligibleAttemptAt

        entry.recordFailure(category: .cancelled, now: start.addingTimeInterval(5))

        #expect(entry.automaticAttemptCount == 1)
        #expect(entry.nextEligibleAttemptAt == dueAfterGenuineFailure)
    }

    /// Four days closed, then one due attempt - not a catch-up burst of every missed deadline.
    @Test
    func reopeningAfterDaysClosedProducesOneAttemptNotACatchUpBurst() {
        let entry = WorkoutSyncOutboxEntry(workoutId: UUID(), ownerUserId: "user-123")
        entry.recordFailure(category: .transient, now: start, randomFraction: 0)

        let fourDaysLater = start.addingTimeInterval(4 * 24 * 60 * 60)
        #expect(entry.isDueForAutomaticAttempt(now: fourDaysLater))
        #expect(entry.automaticAttemptCount == 1)

        entry.recordFailure(category: .transient, now: fourDaysLater, randomFraction: 0)
        #expect(entry.automaticAttemptCount == 2)
        #expect(entry.isDueForAutomaticAttempt(now: fourDaysLater) == false)
    }

    @Test
    func aRefusedSeriesStopsOnlyOnceBothArmsAreSatisfied() {
        let entry = WorkoutSyncOutboxEntry(workoutId: UUID(), ownerUserId: "user-123")

        entry.recordFailure(category: .refused, now: start, randomFraction: 0)
        entry.recordFailure(category: .refused, now: start.addingTimeInterval(5 * 60), randomFraction: 0)
        entry.recordFailure(category: .refused, now: start.addingTimeInterval(20 * 60), randomFraction: 0)

        #expect(entry.refusalCount == 3)
        #expect(entry.hasStoppedAutomaticAttempts(now: start.addingTimeInterval(20 * 60)) == false)
        #expect(entry.hasStoppedAutomaticAttempts(now: start.addingTimeInterval(30 * 60)))
    }

    @Test
    func reopeningRestoresExactlyOneAttempt() {
        let entry = WorkoutSyncOutboxEntry(workoutId: UUID(), ownerUserId: "user-123")
        entry.recordFailure(category: .refused, now: start, randomFraction: 0)
        entry.recordFailure(category: .refused, now: start.addingTimeInterval(5 * 60), randomFraction: 0)
        entry.recordFailure(category: .refused, now: start.addingTimeInterval(35 * 60), randomFraction: 0)
        #expect(entry.hasStoppedAutomaticAttempts(now: start.addingTimeInterval(35 * 60)))

        entry.reopenOneAutomaticAttempt(now: start.addingTimeInterval(40 * 60))

        #expect(entry.hasStoppedAutomaticAttempts(now: start.addingTimeInterval(40 * 60)) == false)
        #expect(entry.isDueForAutomaticAttempt(now: start.addingTimeInterval(40 * 60)))
    }

    @Test
    func aNewPayloadRevisionStartsTheSeriesOver() {
        let entry = WorkoutSyncOutboxEntry(workoutId: UUID(), ownerUserId: "user-123")
        entry.recordFailure(category: .refused, now: start, randomFraction: 0)
        entry.recordFailure(category: .refused, now: start.addingTimeInterval(5 * 60), randomFraction: 0)

        let edited = start.addingTimeInterval(10 * 60)
        entry.resetForNewPayloadRevision(now: edited)

        #expect(entry.automaticAttemptCount == 0)
        #expect(entry.refusalCount == 0)
        #expect(entry.isDueForAutomaticAttempt(now: edited))
    }
}
