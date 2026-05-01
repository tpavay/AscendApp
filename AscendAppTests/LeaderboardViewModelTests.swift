import Foundation
import Testing
@testable import AscendApp

@MainActor
struct LeaderboardViewModelTests {
    @Test
    func cachedFastPathClearsStaleOfflineBannerState() async {
        let cache = LeaderboardSessionCache()
        let userId = UUID().uuidString

        let viewModel = LeaderboardViewModel(sessionCache: cache)
        viewModel.selectedMetric = .climb
        viewModel.selectedTimeFrame = .weekly
        viewModel.isOffline = true
        viewModel.errorMessage = "Offline - showing cached data"

        let stats = [makeRemoteStat(userId: userId, displayName: "User")]
        await cache.setDetailEntries(stats, for: .climb, timeFrame: .weekly)

        await viewModel.loadLeaderboard(userId: userId)

        #expect(viewModel.isOffline == false)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.leaderboardEntries.count == 1)
    }

    private func makeRemoteStat(userId: String, displayName: String) -> FirestoreLeaderboardStats {
        let period = LeaderboardTimeFrame.weekly.currentPeriod(referenceDate: utcDate(year: 2026, month: 4, day: 10))
        let aggregate = LeaderboardAggregate(totalSteps: 1_200, totalFloors: 75, totalWorkouts: 2, totalDuration: 1_800)

        return FirestoreLeaderboardStats(
            userId: userId,
            displayName: displayName,
            photoURL: nil,
            timeFrame: LeaderboardTimeFrame.weekly.rawValue,
            schemaVersion: LeaderboardStats.currentSchemaVersion,
            periodKey: period.key,
            periodStartAt: period.startAt,
            totalSteps: aggregate.totalSteps,
            totalFloors: aggregate.totalFloors,
            totalWorkouts: aggregate.totalWorkouts,
            totalDuration: aggregate.totalDuration,
            stepsPerMinute: aggregate.stepsPerMinute,
            lastUpdated: utcDate(year: 2026, month: 4, day: 10, hour: 8)
        )
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
