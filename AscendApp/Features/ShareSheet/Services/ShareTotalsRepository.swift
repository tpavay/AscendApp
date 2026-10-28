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

    /// The workout figures alone, with no network read, so the stickers can draw at once.
    func snapshot(
        period: SharePeriod,
        modelContext: ModelContext,
        now: Date = Date()
    ) -> ShareTotalsSnapshot {
        ShareTotalsBuilder.make(
            samples: samples(modelContext: modelContext, now: now),
            period: period,
            now: now,
            calendar: calendar
        )
    }

    /// The same snapshot with the three standings read from the leaderboards. Each standing that
    /// cannot be read stays nil, so its sticker is hidden rather than drawn wrong.
    func snapshotWithStandings(
        period: SharePeriod,
        userId: String?,
        modelContext: ModelContext,
        now: Date = Date()
    ) async -> ShareTotalsSnapshot {
        let samples = samples(modelContext: modelContext, now: now)
        guard let userId else {
            return ShareTotalsBuilder.make(samples: samples, period: period, now: now, calendar: calendar)
        }

        async let week = standings.standing(userId: userId, timeFrame: .weekly)
        async let month = standings.standing(userId: userId, timeFrame: .monthly)
        async let year = standings.standing(userId: userId, timeFrame: .yearly)
        return ShareTotalsBuilder.make(
            samples: samples,
            period: period,
            now: now,
            calendar: calendar,
            weekStanding: await week,
            monthStanding: await month,
            yearStanding: await year
        )
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
