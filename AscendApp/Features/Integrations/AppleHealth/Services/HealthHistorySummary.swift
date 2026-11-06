import Foundation

/// What Apple Health already holds for the climber, read before they have an account, for onboarding's
/// "We found your climbs".
///
/// Read-only and filed nowhere: this is a look, and the import itself waits for sign-in
/// (`AppleHealthImportService.importHistory(matching:)`). Unlike the pass it has no join-date floor,
/// because the screen is about the history the pass would never reach.
///
/// Steps are the ones an import would keep (`AppleHealthImportPolicy.importableSteps`), so the
/// number on screen is the number that lands. A stair stepper workout usually carries none, and
/// unknown is never zero: every figure built from steps counts only the workouts that report them.
struct HealthHistorySummary: Equatable, Sendable {
    /// The usual climb: the median of the last 30 days, else of everything.
    struct UsualClimb: Equatable, Sendable {
        /// Nil when no workout in the set reported steps, which leaves the minutes to stand alone.
        let steps: Int?
        let minutes: Int
    }

    /// How far back "usual" looks before it falls back to everything.
    static let usualClimbWindow: TimeInterval = 30 * 24 * 60 * 60

    /// The shortest workout a "best hour" can be read from. A shorter one proves nothing about an
    /// hour, which is the same rule the app's own 60-minute record keeps.
    static let bestHourSeconds: TimeInterval = 60 * 60

    /// The workouts found, every one a climb an import would file.
    let workoutIDs: [String]
    let totalDuration: TimeInterval
    /// How many of them carry a step count.
    let workoutsWithSteps: Int
    /// The sum of the steps those workouts report.
    let knownSteps: Int
    let bestHourSteps: Int?
    let usualClimb: UsualClimb?

    var workoutCount: Int { workoutIDs.count }

    var isEmpty: Bool { workoutIDs.isEmpty }

    /// Whether the headline is the steps total: at least half of the workouts report steps. With
    /// fewer, the screen leads with the count and the hours and the steps wait behind them.
    var leadsWithSteps: Bool {
        knownSteps > 0 && workoutsWithSteps * 2 >= workoutCount
    }

    /// The workouts' total time as the screen says it: minutes under an hour, else whole hours.
    var totalDurationText: String {
        let minutes = Int((totalDuration / 60).rounded())
        guard minutes >= 60 else { return "\(max(minutes, 1)) min" }
        let hours = Int((totalDuration / 3600).rounded())
        return hours == 1 ? "1 hour" : "\(hours.formatted()) hours"
    }

    /// Builds the summary from every stair workout Health returned.
    static func make(from workouts: [HealthWorkoutSnapshot], now: Date) -> HealthHistorySummary {
        let climbs = workouts
            .filter { AppleHealthImportPolicy.isImportableDuration($0.duration) }
            .map { Measured(workout: $0) }

        let withSteps = climbs.filter { $0.steps != nil }
        let known = withSteps.reduce(0) { $0 + ($1.steps ?? 0) }

        return HealthHistorySummary(
            workoutIDs: climbs.map(\.workout.uuid.uuidString),
            totalDuration: climbs.reduce(0) { $0 + $1.workout.duration },
            workoutsWithSteps: withSteps.count,
            knownSteps: known,
            bestHourSteps: bestHour(in: withSteps),
            usualClimb: usualClimb(in: climbs, now: now)
        )
    }

    /// Reads every stair workout Health holds, from the beginning, and summarises it. Throws when
    /// the read fails, which a caller reads as "nothing to show", never as an empty history.
    ///
    /// The anchor the read returns is dropped on purpose. It belongs to the pass, which stores its
    /// own and reads from the join date on.
    @MainActor
    static func load(using reader: any HealthWorkoutReading, now: Date = Date()) async throws -> HealthHistorySummary {
        let found = try await reader.changes(since: nil, startingOnOrAfter: .distantPast)
        return make(from: found.added, now: now)
    }

    // MARK: - Derivations

    private struct Measured {
        let workout: HealthWorkoutSnapshot
        let steps: Int?

        init(workout: HealthWorkoutSnapshot) {
            self.workout = workout
            steps = AppleHealthImportPolicy.importableSteps(workout.steps, duration: workout.duration)
        }
    }

    /// The most steps one hour held, read from a workout of at least an hour by spreading its steps
    /// evenly over its time, which is how an import records it (a workout has totals, not a curve).
    private static func bestHour(in climbs: [Measured]) -> Int? {
        let hours = climbs.compactMap { climb -> Int? in
            guard let steps = climb.steps, climb.workout.duration >= bestHourSeconds else { return nil }
            return Int((Double(steps) * bestHourSeconds / climb.workout.duration).rounded())
        }
        return hours.max()
    }

    private static func usualClimb(in climbs: [Measured], now: Date) -> UsualClimb? {
        guard !climbs.isEmpty else { return nil }

        let recent = climbs.filter { now.timeIntervalSince($0.workout.startDate) <= usualClimbWindow }
        let set = recent.isEmpty ? climbs : recent

        let withSteps = set.filter { $0.steps != nil }
        guard !withSteps.isEmpty else {
            return UsualClimb(steps: nil, minutes: wholeMinutes(median(set.map(\.workout.duration))))
        }
        return UsualClimb(
            steps: Int(median(withSteps.compactMap { $0.steps.map(Double.init) }).rounded()),
            minutes: wholeMinutes(median(withSteps.map(\.workout.duration)))
        )
    }

    private static func wholeMinutes(_ seconds: Double) -> Int {
        max(Int((seconds / 60).rounded()), 1)
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

/// What the climber's steps are the height of: Everest, or when they are under one, the tallest
/// climb they have already covered. The line under 07a's total.
struct HealthHistoryComparison: Equatable, Sendable {
    /// Mount Everest's step count in the climb catalogue, the one the design compares to.
    static let everestSteps = 48_664

    let name: String
    let isEverest: Bool
    /// Whole times the steps cover it, never less than one.
    let timesOver: Int

    /// Everest when the steps reach it, else the tallest available climb they reach, else nil.
    /// Only the steps a workout reported count, so no known steps means no comparison.
    static func make(knownSteps: Int, climbs: [Climb]) -> HealthHistoryComparison? {
        guard knownSteps > 0 else { return nil }

        if knownSteps >= everestSteps {
            return HealthHistoryComparison(name: "Everest", isEverest: true, timesOver: knownSteps / everestSteps)
        }

        let reached = climbs
            .filter { $0.isAvailable && $0.referenceStepCount > 0 && $0.referenceStepCount <= knownSteps }
            .max { $0.referenceStepCount < $1.referenceStepCount }
        guard let reached else { return nil }

        return HealthHistoryComparison(
            name: reached.name,
            isEverest: false,
            timesOver: knownSteps / reached.referenceStepCount
        )
    }

    /// The words that make a name a thing you say "the" before: a building, a tower, a centre. They
    /// can sit anywhere in it - the Leaning Tower of Pisa, the Statue of Liberty. A name without one
    /// (Taipei 101, Merdeka 118, Monserrate, Burj Khalifa) is a proper name on its own, and "the" in
    /// front of it reads wrong on a screen a new climber sees first.
    private static let articleNouns: Set<String> = [
        "Building", "Tower", "Towers", "Centre", "Center", "Needle", "Monument",
        "Plaza", "Square", "Stair", "Statue"
    ]

    /// Names that hold one of those words and are still said bare.
    private static let bareNames: Set<String> = ["One World Trade Center"]

    private static func carriesArticle(_ name: String) -> Bool {
        guard !bareNames.contains(name) else { return false }
        return name.split(separator: " ").contains { articleNouns.contains(String($0)) }
    }

    /// The card's kicker.
    var kicker: String {
        if isEverest { return "That's Everest" }
        return Self.carriesArticle(name) ? "That's the \(name)" : "That's \(name)"
    }

    var timesOverText: String {
        timesOver == 1 ? "1 time over." : "\(timesOver.formatted()) times over."
    }

    /// How many peaks the card draws: one per time over, up to what a row can hold.
    static let maximumPeaks = 20

    var peakCount: Int { min(timesOver, Self.maximumPeaks) }
}
