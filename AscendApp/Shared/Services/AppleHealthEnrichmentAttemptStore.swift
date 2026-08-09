import Foundation

/// One climb's place in the enrichment retry curve.
struct AppleHealthEnrichmentAttempt: Codable, Equatable, Sendable {
    /// Attempts already spent, the save-time one included.
    var attemptCount: Int
    /// When the most recent attempt ran. Retires the entry once its climb is far enough in
    /// the past that no schedule could still reach it.
    var lastAttemptAt: Date
    /// The absolute instant the next automatic attempt becomes eligible, or `nil` once the
    /// budget is spent and no further automatic attempt is coming.
    var nextEligibleAt: Date?
}

/// The persisted ledger deciding when enrichment may look at Apple Health again.
///
/// Eligibility is a stored absolute date rather than a counter with a cooldown, because
/// several surfaces can ask for the same climb in the same millisecond - the completion
/// summary, the workout detail, the scheduler's own timer and an app foreground all reach
/// the same entry point - and three callers sharing one counter would spend three attempts
/// on one instant. An absolute date is unanimous no matter who reads it, and it survives
/// relaunch, so a climber who force-quits does not get a fresh budget.
struct AppleHealthEnrichmentAttemptStore {
    private let defaults: UserDefaults
    private let key: String

    /// The curve this ledger enforces, and the only copy of it. Every collaborator reads it
    /// back from here rather than holding its own, so no two of them can disagree about when
    /// the same climb is due.
    let schedule: AppleHealthEnrichmentSchedule

    init(
        defaults: UserDefaults = .standard,
        key: String = "appleHealth.enrichmentAttempts.byWorkoutID",
        schedule: AppleHealthEnrichmentSchedule = .standard
    ) {
        self.defaults = defaults
        self.key = key
        self.schedule = schedule
    }

    func attempt(for workoutID: UUID) -> AppleHealthEnrichmentAttempt? {
        attempts()[workoutID.uuidString]
    }

    /// Whether an automatic attempt may run now.
    ///
    /// A climb with no ledger entry is due: that is the save-time attempt. After that the
    /// stored date is the only authority, and a spent budget (`nextEligibleAt == nil`) is
    /// never due again.
    func isAutomaticAttemptDue(for workout: Workout, at date: Date = Date()) -> Bool {
        guard schedule.isWithinEligibilityWindow(workout, at: date) else { return false }

        guard let attempt = attempt(for: workout.id) else { return true }
        guard let nextEligibleAt = attempt.nextEligibleAt else { return false }
        return date >= nextEligibleAt
    }

    /// Whether the automatic series has run out for this climb, so the UI should say it has
    /// stopped looking rather than that it is still waiting.
    func hasExhaustedAutomaticAttempts(for workout: Workout, at date: Date = Date()) -> Bool {
        guard schedule.isWithinEligibilityWindow(workout, at: date) else { return true }
        guard let attempt = attempt(for: workout.id) else { return false }
        return attempt.nextEligibleAt == nil
    }

    /// When the next automatic attempt for this climb comes due, if one is still coming.
    func nextEligibleDate(for workout: Workout, at date: Date = Date()) -> Date? {
        guard schedule.isWithinEligibilityWindow(workout, at: date) else { return nil }
        guard let attempt = attempt(for: workout.id) else { return date }
        return attempt.nextEligibleAt
    }

    /// Spends one attempt and writes the instant the next one becomes eligible.
    func recordAttempt(for workout: Workout, at date: Date = Date()) {
        var ledger = prunedAttempts(attempts(), at: date)
        let spent = (ledger[workout.id.uuidString]?.attemptCount ?? 0) + 1

        ledger[workout.id.uuidString] = AppleHealthEnrichmentAttempt(
            attemptCount: spent,
            lastAttemptAt: date,
            nextEligibleAt: schedule.delay(afterAttempt: spent).map(date.addingTimeInterval)
        )

        write(ledger)
    }

    func clear(workoutID: UUID) {
        var ledger = attempts()
        guard ledger.removeValue(forKey: workoutID.uuidString) != nil else { return }
        write(ledger)
    }

    /// Drops entries whose climb can no longer be eligible under any schedule.
    ///
    /// Keyed by workout ID with no back-reference to the store, an entry has no other way to
    /// learn its climb was deleted, so the clock is what retires it. Pruning reads the last
    /// attempt rather than the next one: a spent budget has no next attempt, and that is
    /// exactly the entry the UI needs in order to say Ascend has stopped looking instead of
    /// silently starting the series over. Twice the window is deliberate slack - the entry
    /// costs a few bytes, and retiring one early hands its climb a second budget.
    func prune(at date: Date = Date()) {
        let current = attempts()
        let pruned = prunedAttempts(current, at: date)

        // `resumeTracking` prunes on every foreground and every workout-detail open, and the
        // ledger is unchanged nearly every time. Writing regardless would spend a JSON encode
        // and a `UserDefaults.set` per navigation to store what is already there.
        guard pruned.count != current.count else { return }
        write(pruned)
    }

    private func prunedAttempts(
        _ ledger: [String: AppleHealthEnrichmentAttempt],
        at date: Date
    ) -> [String: AppleHealthEnrichmentAttempt] {
        let horizon = schedule.eligibilityWindow * 2
        return ledger.filter { _, attempt in
            date.timeIntervalSince(attempt.lastAttemptAt) <= horizon
        }
    }

    private func attempts() -> [String: AppleHealthEnrichmentAttempt] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(
                [String: AppleHealthEnrichmentAttempt].self,
                from: data
              ) else {
            return [:]
        }

        return decoded
    }

    private func write(_ ledger: [String: AppleHealthEnrichmentAttempt]) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        defaults.set(data, forKey: key)
    }
}
