import Foundation
import Testing
@testable import AscendApp

struct LeaderboardCurrentUserReconcilerTests {
    @Test
    func previewReconciliationUpdatesCurrentUserAndResortsMetric() {
        let period = LeaderboardTimeFrame.weekly.currentPeriod(referenceDate: utcDate(year: 2026, month: 4, day: 14))
        let localStats = LeaderboardStats(
            userId: "me",
            timeFrame: .weekly,
            period: period,
            totalSteps: 200,
            totalFloors: 10,
            totalWorkouts: 2,
            totalDuration: 1_200,
            stepsPerMinute: 10
        )

        let original = [
            LeaderboardMetric.climb: [
                makeRemoteStat(userId: "other", displayName: "Other", steps: 150, period: period),
                makeRemoteStat(userId: "me", displayName: "Old Me", steps: 123, period: period)
            ]
        ]

        let reconciled = LeaderboardCurrentUserReconciler.reconcilePreviewStats(
            original,
            userId: "me",
            localStats: localStats
        )

        let climbStats = try! #require(reconciled[.climb])
        #expect(climbStats.count == 2)
        #expect(climbStats[0].userId == "me")
        #expect(climbStats[0].displayName == "You")
        #expect(climbStats[0].photoURL == nil)
        #expect(climbStats[0].totalSteps == 200)
    }

    @Test
    func detailReconciliationRemovesCurrentUserWhenLocalStatsHaveNoActivity() {
        let period = LeaderboardTimeFrame.weekly.currentPeriod(referenceDate: utcDate(year: 2026, month: 4, day: 14))
        let localStats = LeaderboardStats(
            userId: "me",
            timeFrame: .weekly,
            period: period,
            totalSteps: 0,
            totalFloors: 0,
            totalWorkouts: 0,
            totalDuration: 0,
            stepsPerMinute: 0
        )

        let original = [
            makeRemoteStat(userId: "me", displayName: "Old Me", steps: 123, period: period),
            makeRemoteStat(userId: "other", displayName: "Other", steps: 75, period: period)
        ]

        let reconciled = LeaderboardCurrentUserReconciler.reconcileDetailStats(
            original,
            metric: .climb,
            userId: "me",
            localStats: localStats
        )

        #expect(reconciled.count == 1)
        #expect(reconciled[0].userId == "other")
    }

    @Test
    func previewReconciliationInsertsCurrentUserWhenRemoteCacheIsMissingRow() {
        let period = LeaderboardTimeFrame.weekly.currentPeriod(referenceDate: utcDate(year: 2026, month: 4, day: 14))
        let localStats = LeaderboardStats(
            userId: "me",
            timeFrame: .weekly,
            period: period,
            totalSteps: 80,
            totalFloors: 8,
            totalWorkouts: 1,
            totalDuration: 900,
            stepsPerMinute: 5.3
        )

        let original = [
            LeaderboardMetric.climb: [
                makeRemoteStat(userId: "other", displayName: "Other", steps: 60, period: period)
            ]
        ]

        let reconciled = LeaderboardCurrentUserReconciler.reconcilePreviewStats(
            original,
            userId: "me",
            localStats: localStats
        )

        let climbStats = try! #require(reconciled[.climb])
        #expect(climbStats.count == 2)
        #expect(climbStats[0].userId == "me")
        #expect(climbStats[0].displayName == "You")
        #expect(climbStats[0].totalSteps == 80)
    }

    private func makeRemoteStat(
        userId: String,
        displayName: String,
        steps: Int,
        period: LeaderboardPeriod
    ) -> FirestoreLeaderboardStats {
        let aggregate = LeaderboardAggregate(totalSteps: steps, totalFloors: 5, totalWorkouts: 1, totalDuration: 900)
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
            lastUpdated: utcDate(year: 2026, month: 4, day: 14, hour: 12)
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
