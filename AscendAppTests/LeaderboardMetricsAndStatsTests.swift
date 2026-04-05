import Foundation
import Testing
@testable import AscendApp

struct LeaderboardMetricsAndStatsTests {
    @Test
    func leaderboardMetricsIgnoreViewerPreferredFloorsSetting() {
        #expect(LeaderboardMetric.climb.displayName(for: .floors) == "Steps")
        #expect(LeaderboardMetric.climb.unit(for: .floors) == "steps")
        #expect(LeaderboardMetric.pace.displayName(for: .floors) == "Steps/Min")
        #expect(LeaderboardMetric.pace.unit(for: .floors) == "steps/min")
    }

    @Test
    func leaderboardStatsRecalculateCanonicalStepsPerMinuteFromTotals() {
        let period = LeaderboardTimeFrame.weekly.currentPeriod(referenceDate: utcDate(year: 2026, month: 4, day: 10))
        let stats = LeaderboardStats(userId: "user-1", timeFrame: .weekly, period: period)

        stats.replaceTotals(
            with: LeaderboardAggregate(totalSteps: 1_200, totalFloors: 75, totalWorkouts: 1, totalDuration: 1_800),
            period: period,
            updatedAt: utcDate(year: 2026, month: 4, day: 10, hour: 8)
        )
        stats.apply(
            delta: LeaderboardAggregate(totalSteps: 600, totalFloors: 40, totalWorkouts: 1, totalDuration: 900),
            period: period,
            updatedAt: utcDate(year: 2026, month: 4, day: 10, hour: 9)
        )

        #expect(stats.totalSteps == 1_800)
        #expect(stats.totalDuration == 2_700)
        #expect(stats.stepsPerMinute == 40)
        #expect(stats.value(for: .climb) == 1_800)
        #expect(stats.value(for: .pace) == 40)
    }

    @Test
    func leaderboardStatsClampNegativeDeltasAtZero() {
        let period = LeaderboardTimeFrame.weekly.currentPeriod(referenceDate: utcDate(year: 2026, month: 4, day: 10))
        let stats = LeaderboardStats(userId: "user-1", timeFrame: .weekly, period: period)

        stats.apply(
            delta: LeaderboardAggregate(totalSteps: -500, totalFloors: -30, totalWorkouts: -1, totalDuration: -600),
            period: period,
            updatedAt: utcDate(year: 2026, month: 4, day: 10, hour: 9)
        )

        #expect(stats.totalSteps == 0)
        #expect(stats.totalFloors == 0)
        #expect(stats.totalWorkouts == 0)
        #expect(stats.totalDuration == 0)
        #expect(stats.stepsPerMinute == 0)
    }

    private func utcDate(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = WeekConfiguration.calendar(timeZone: LeaderboardTimeFrame.canonicalTimeZone)
        components.timeZone = LeaderboardTimeFrame.canonicalTimeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return components.date!
    }
}
