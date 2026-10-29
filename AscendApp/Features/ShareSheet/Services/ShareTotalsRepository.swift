import Foundation
import SwiftData

/// Loads the Totals stickers' data: a date-bounded read of the climber's own workouts plus their
/// steps standing on the weekly, monthly and yearly boards.
///
/// The fetch is bounded by `ShareTotalsBuilder.earliestNeededDate` and loads only the four
/// columns a figure needs, because a `Workout` carries its heart-rate series inline and a whole
/// history scan costs more with every climb.
@MainActor
struct ShareTotalsRepository {
    private let standings: any ShareStandingReading
    private let calendar: Calendar

    init(
        standings: any ShareStandingReading = LeaderboardShareStandingReader(),
        calendar: Calendar = WeekConfiguration.calendar()
    ) {
        self.standings = standings
        self.calendar = calendar
    }

    /// Where the climber stands on the weekly, monthly and yearly steps boards. These do not
    /// depend on the period a sticker shows, so a sheet reads them once.
    struct Standings: Equatable, Sendable {
        var week: ShareTotalsSnapshot.Standing?
        var month: ShareTotalsSnapshot.Standing?
        var year: ShareTotalsSnapshot.Standing?

        static let none = Standings()
    }

    /// The workout figures for `period`, local and immediate, with whatever standings are known.
    func snapshot(
        period: SharePeriod,
        modelContext: ModelContext,
        standings: Standings = .none,
        now: Date = Date()
    ) -> ShareTotalsSnapshot {
        ShareTotalsBuilder.make(
            samples: samples(modelContext: modelContext, now: now),
            period: period,
            now: now,
            calendar: calendar,
            weekStanding: standings.week,
            monthStanding: standings.month,
            yearStanding: standings.year
        )
    }

    /// The three standings read from the leaderboards. Each one that cannot be read stays nil,
    /// so its sticker is hidden rather than drawn wrong.
    func standings(userId: String?) async -> Standings {
        guard let userId else { return .none }
        async let week = standings.standing(userId: userId, timeFrame: .weekly)
        async let month = standings.standing(userId: userId, timeFrame: .monthly)
        async let year = standings.standing(userId: userId, timeFrame: .yearly)
        return Standings(week: await week, month: await month, year: await year)
    }

    private func samples(modelContext: ModelContext, now: Date) -> [ShareTotalsBuilder.Sample] {
        let earliest = ShareTotalsBuilder.earliestNeededDate(now: now, calendar: calendar)
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.date >= earliest && $0.date <= now }
        )
        descriptor.propertiesToFetch = [\.date, \.steps, \.duration]
        let workouts = (try? modelContext.fetch(descriptor)) ?? []
        return workouts.map { ShareTotalsBuilder.Sample(date: $0.date, steps: $0.steps, duration: $0.duration) }
    }
}
