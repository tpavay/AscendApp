import Foundation
import Testing
@testable import AscendApp

struct LeaderboardSessionCacheTests {
    @Test
    func cacheUpdatesCurrentUserAcrossPreviewAndDetailEntries() async {
        let cache = LeaderboardSessionCache()

        let weeklyStats = [
            makeRemoteStat(userId: "current-user", displayName: "Before", photoURL: "https://example.com/before.png", steps: 1_200, floors: 75),
            makeRemoteStat(userId: "other-user", displayName: "Other", photoURL: nil, steps: 900, floors: 60)
        ]
        let monthlyStats = [
            makeRemoteStat(userId: "current-user", displayName: "Before", photoURL: "https://example.com/before.png", steps: 4_000, floors: 250, timeFrame: .monthly)
        ]

        await cache.setDetailEntries(weeklyStats, for: .climb, timeFrame: .weekly)
        await cache.setDetailEntries(monthlyStats, for: .climb, timeFrame: .monthly)
        await cache.setPreviewEntries([.climb: weeklyStats], for: .weekly)

        let updatedPhotoURL = URL(string: "https://example.com/after.png")
        await cache.updateCurrentUserProfile(userId: "current-user", displayName: "After", photoURL: updatedPhotoURL)

        let weeklyDetail = await cache.detailEntries(for: .climb, timeFrame: .weekly)
        let monthlyDetail = await cache.detailEntries(for: .climb, timeFrame: .monthly)
        let weeklyPreview = await cache.previewEntries(for: .weekly)

        #expect(weeklyDetail?.first?.displayName == "After")
        #expect(weeklyDetail?.first?.photoURL == updatedPhotoURL?.absoluteString)
        #expect(monthlyDetail?.first?.displayName == "After")
        #expect(weeklyPreview?[.climb]?.first?.displayName == "After")
        #expect(weeklyDetail?.last?.displayName == "Other")

        await cache.invalidate(timeFrame: .weekly)
        #expect(await cache.detailEntries(for: .climb, timeFrame: .weekly) == nil)
        #expect(await cache.previewEntries(for: .weekly) == nil)
        #expect(await cache.detailEntries(for: .climb, timeFrame: .monthly)?.count == 1)
    }

    private func makeRemoteStat(
        userId: String,
        displayName: String,
        photoURL: String?,
        steps: Int,
        floors: Int,
        timeFrame: LeaderboardTimeFrame = .weekly
    ) -> FirestoreLeaderboardStats {
        let period = timeFrame.currentPeriod(referenceDate: utcDate(year: 2026, month: 4, day: 10))
        let aggregate = LeaderboardAggregate(
            totalSteps: steps,
            totalFloors: floors,
            totalWorkouts: 2,
            totalDuration: 1_800
        )

        return FirestoreLeaderboardStats(
            userId: userId,
            displayName: displayName,
            photoURL: photoURL,
            timeFrame: timeFrame.rawValue,
            schemaVersion: LeaderboardStats.currentSchemaVersion,
            periodKey: period.key,
            periodStartAt: period.startAt,
            totalSteps: steps,
            totalFloors: floors,
            totalWorkouts: 2,
            totalDuration: 1_800,
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
