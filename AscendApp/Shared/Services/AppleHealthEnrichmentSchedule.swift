import Foundation

/// The bounded retry curve enrichment follows while it waits for a wearable to publish
/// heart-rate samples into Apple Health.
///
/// A climber's watch is not the only writer, and the writers do not agree on when they write.
/// An Apple Watch publishes within seconds of the session ending; Garmin, Whoop and Polar
/// publish when their companion app next syncs, which is minutes at best and hours when the
/// phone was asleep. One read at save time answers for none of them, and an unbounded poll
/// answers for all of them at a cost no climber agreed to pay.
///
/// So the curve is dense where the answer usually arrives and sparse where it merely might,
/// and it ends: nine attempts reach roughly ten hours past the climb. After that the climber
/// can still fetch by hand and Ascend stops asking on its own.
struct AppleHealthEnrichmentSchedule: Sendable, Equatable {
    static let standard = AppleHealthEnrichmentSchedule()

    /// Delay from each attempt to the next one. The first attempt runs when the climb is
    /// saved, and every entry here buys exactly one more - so this array *is* the retry
    /// budget, and exhausting it is what stops the series.
    let backoff: [TimeInterval]

    /// Nothing is tracked automatically past this, measured from the end of the climb.
    ///
    /// The backoff runs out long before this does. The window exists for the workouts the
    /// backoff never covered - one hydrated onto a fresh device, one whose ledger entry was
    /// lost - so an old climb can still be picked up once without re-opening the whole
    /// history to background reads.
    let eligibilityWindow: TimeInterval

    init(
        backoff: [TimeInterval] = [15, 45, 120, 300, 900, 2_700, 7_200, 21_600],
        eligibilityWindow: TimeInterval = 72 * 60 * 60
    ) {
        self.backoff = backoff
        self.eligibilityWindow = eligibilityWindow
    }

    /// How many automatic attempts a single climb ever gets, the save-time one included.
    var attemptBudget: Int { backoff.count + 1 }

    /// How long to wait before attempt number `attemptCount + 1`, or `nil` once the budget
    /// is spent.
    func delay(afterAttempt attemptCount: Int) -> TimeInterval? {
        guard attemptCount >= 1, attemptCount <= backoff.count else { return nil }
        return backoff[attemptCount - 1]
    }

    /// Whether `date` is still inside the window measured from the end of `workout`.
    ///
    /// The small negative tolerance covers a workout whose stored end is a moment in the
    /// future relative to the clock that asks - a session saved as it ends.
    func isWithinEligibilityWindow(_ workout: Workout, at date: Date) -> Bool {
        let secondsSinceEnd = date.timeIntervalSince(Self.endDate(of: workout))
        return secondsSinceEnd >= -60 && secondsSinceEnd <= eligibilityWindow
    }

    static func endDate(of workout: Workout) -> Date {
        workout.date.addingTimeInterval(max(workout.duration, 1))
    }
}
