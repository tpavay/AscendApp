import Foundation

/// How a failed remote outcome is treated, and what it means for the retry series.
///
/// The pinned Firestore SDK (11.15.0) already retries its own transport for a submitted mutation,
/// so this layer is not a second network retry. It decides when to re-offer a *logical* backup that
/// the SDK is no longer carrying - a surfaced rejection, a pre-enqueue failure, or a sidecar
/// operation it never owned.
enum WorkoutSyncFailureCategory: String, Equatable, Sendable, CaseIterable {
    /// The enclosing task went away. Not evidence of anything, and it consumes no attempt.
    case cancelled
    /// The device is known offline. Consumes no attempt; the row says so and the control is dead.
    case offline
    /// A later attempt could genuinely differ: connectivity, timeouts, throttling, backend churn.
    case transient
    /// Credentials need repair. One reconciliation, then the climber has to act.
    case authentication
    /// The server refused these bytes. Ambiguous by construction - see `permissionDenied` below.
    case refused
    /// The request itself is unacceptable and an identical one cannot become acceptable.
    case malformed

    /// Whether a genuine remote verdict was reached, and therefore whether the attempt counts.
    ///
    /// Offline deferral and lifecycle cancellation are the two that must not: charging them turns
    /// a tab switch into evidence, which is exactly how one workout produced 499 events.
    var consumesAttempt: Bool {
        switch self {
        case .cancelled, .offline:
            return false
        case .transient, .authentication, .refused, .malformed:
            return true
        }
    }

    /// Whether the climber has to be told immediately rather than after the quiet window.
    ///
    /// A refusal is deliberately NOT immediate. The incident that prompted this work proved a
    /// deployable rules defect produces the same code as a genuine authorization failure, so a
    /// refusal earns the elapsed-time gate rather than an instant verdict.
    var requiresImmediateAttention: Bool {
        self == .malformed
    }
}

/// The coarse, persisted, time-spaced schedule Ascend re-offers a backup on.
///
/// Deliberately far coarser than Firestore's own 1s-to-60s transport backoff: this layer's job is
/// to decide when a *logical* backup is worth re-offering, not to retransmit packets. Stacking a
/// rapid loop on the SDK's rapid loop multiplies network, battery and backend load for nothing.
///
/// The gate is `now >= nextEligibleAttemptAt`, persisted as an absolute date. A count alone is not
/// enough and never was: seven surfaces call the coordinator, a re-entrant call re-runs the pending
/// query, and three triggers can consume three attempts in the same millisecond - which is the
/// defect this schedule exists to close.
enum WorkoutSyncRetryPolicy {
    /// No-earlier-than offsets, in seconds, for each successive automatic attempt.
    ///
    /// Seven entries, so the series ends after the attempt due at 24 hours has failed. Both halves
    /// of that are required: the count alone can be burned through, and the clock alone would
    /// retry forever at a slow rate.
    static let attemptOffsets: [TimeInterval] = [
        0,
        60,
        5 * 60,
        15 * 60,
        60 * 60,
        6 * 60 * 60,
        24 * 60 * 60
    ]

    /// How many genuine attempts complete the automatic series.
    static var maximumAutomaticAttempts: Int { attemptOffsets.count }

    /// How long a workout may sit unacknowledged before the climber is told.
    static let attentionThreshold: TimeInterval = 30 * 60

    /// A refusal needs BOTH of these before automatic attempts stop.
    ///
    /// Conjunctive on purpose. Three denials can arrive in one millisecond during a launch burst;
    /// requiring 30 elapsed minutes as well means a brief rules-deploy window, an App Check hiccup
    /// or an unpropagated token after an account switch cannot condemn the queue.
    static let refusalsBeforeStopping = 3
    static let refusalElapsedBeforeStopping: TimeInterval = 30 * 60

    /// Upward-only jitter, so the no-earlier-than guarantee survives it.
    ///
    /// Downward jitter would let an attempt land before its own due time, which is the one thing
    /// the persisted date is for. Upward still breaks up the fleet-wide spike after a shared
    /// outage or a rules deploy.
    static let maximumJitterFraction = 0.20

    /// The next due date after `attemptCount` genuine attempts, or nil once the series is done.
    ///
    /// `randomFraction` is injected so a test can pin the jitter instead of tolerating a range.
    static func nextEligibleAttemptDate(
        afterAttemptCount attemptCount: Int,
        from referenceDate: Date,
        randomFraction: Double = Double.random(in: 0...1)
    ) -> Date? {
        guard attemptCount >= 0, attemptCount < attemptOffsets.count else { return nil }

        let offset = attemptOffsets[attemptCount]
        let jitter = offset * maximumJitterFraction * min(max(randomFraction, 0), 1)
        return referenceDate.addingTimeInterval(offset + jitter)
    }

    /// Whether the automatic series has run out for this workout.
    ///
    /// Requires the whole schedule to have been walked AND the last offset to have elapsed, so a
    /// burst of triggers cannot retire a workout early.
    static func hasExhaustedAutomaticAttempts(
        attemptCount: Int,
        firstPendingAt: Date?,
        now: Date
    ) -> Bool {
        guard attemptCount >= maximumAutomaticAttempts else { return false }
        guard let firstPendingAt, let finalOffset = attemptOffsets.last else { return true }

        return now.timeIntervalSince(firstPendingAt) >= finalOffset
    }

    /// Whether repeated refusals have earned a stop. Both arms must be true.
    static func refusalsHaveEarnedStop(
        refusalCount: Int,
        firstPendingAt: Date?,
        now: Date
    ) -> Bool {
        guard refusalCount >= refusalsBeforeStopping else { return false }
        guard let firstPendingAt else { return false }

        return now.timeIntervalSince(firstPendingAt) >= refusalElapsedBeforeStopping
    }

    /// Whether the climber should be told, given how long this has been unacknowledged.
    static func requiresAttention(
        category: WorkoutSyncFailureCategory?,
        firstPendingAt: Date?,
        now: Date
    ) -> Bool {
        if let category, category.requiresImmediateAttention { return true }
        guard let firstPendingAt else { return false }

        return now.timeIntervalSince(firstPendingAt) >= attentionThreshold
    }

    /// Keeps a persisted date usable after the device clock moves.
    ///
    /// A clock pushed far forward would otherwise let every deadline fall due at once, and one
    /// pushed far back would park a workout past any plausible horizon. Both are clamped to the
    /// schedule's own bounds rather than trusted.
    static func clampedEligibilityDate(_ date: Date, now: Date) -> Date {
        guard let finalOffset = attemptOffsets.last else { return now }
        let horizon = now.addingTimeInterval(finalOffset * (1 + maximumJitterFraction))

        if date < now { return now }
        if date > horizon { return horizon }
        return date
    }
}
