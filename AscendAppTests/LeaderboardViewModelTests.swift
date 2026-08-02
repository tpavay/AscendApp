import Foundation
import SwiftData
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

    @Test
    func durationMetricFormatsAsHoursMinutesSeconds() async {
        let cache = LeaderboardSessionCache()
        let userId = UUID().uuidString
        let totalDuration = Double((176 * 3_600) + (12 * 60) + 12)

        let viewModel = LeaderboardViewModel(sessionCache: cache)
        viewModel.selectedMetric = .duration
        viewModel.selectedTimeFrame = .weekly

        let stats = [makeRemoteStat(userId: userId, displayName: "User", totalDuration: totalDuration)]
        await cache.setDetailEntries(stats, for: .duration, timeFrame: .weekly)

        await viewModel.loadLeaderboard(userId: userId)

        #expect(viewModel.leaderboardEntries.first?.formattedValue == "176:12:12")
    }

    @Test
    func tiedStepTotalsShareARankAndSkipTheNextOne() async {
        let cache = LeaderboardSessionCache()

        let viewModel = LeaderboardViewModel(sessionCache: cache)
        viewModel.selectedMetric = .climb
        viewModel.selectedTimeFrame = .weekly

        // Descending by steps, then uid — the ordering the repository and the Cloud
        // Function both produce. The uid tiebreak must not leak into the rank.
        let stats = [
            makeRemoteStat(userId: "aaa", displayName: "Leader", totalSteps: 9_000),
            makeRemoteStat(userId: "mmm", displayName: "Tied A", totalSteps: 5_000),
            makeRemoteStat(userId: "zzz", displayName: "Tied B", totalSteps: 5_000),
            makeRemoteStat(userId: "bbb", displayName: "Trailer", totalSteps: 1_000)
        ]
        await cache.setDetailEntries(stats, for: .climb, timeFrame: .weekly)

        await viewModel.loadLeaderboard(userId: "mmm")

        #expect(viewModel.leaderboardEntries.map(\.rank) == [1, 2, 2, 4])
        #expect(viewModel.leaderboardEntries.map(\.isTied) == [false, true, true, false])
    }

    @Test
    func tiedCurrentUserSeesTheSameRankOnTheirPinnedRowAsInTheList() async {
        // The reported bug: the pinned row and the list row disagreed for a tied user.
        let cache = LeaderboardSessionCache()

        let viewModel = LeaderboardViewModel(sessionCache: cache)
        viewModel.selectedMetric = .climb
        viewModel.selectedTimeFrame = .weekly

        let stats = [
            makeRemoteStat(userId: "aaa", displayName: "Leader", totalSteps: 9_000),
            makeRemoteStat(userId: "mmm", displayName: "Rival", totalSteps: 5_000),
            makeRemoteStat(userId: "zzz", displayName: "You", totalSteps: 5_000)
        ]
        await cache.setDetailEntries(stats, for: .climb, timeFrame: .weekly)

        await viewModel.loadLeaderboard(userId: "zzz")

        let listEntry = viewModel.leaderboardEntries.first { $0.userId == "zzz" }
        #expect(listEntry?.rank == 2)
        #expect(listEntry?.isTied == true)
        #expect(viewModel.userStanding?.rankedEntry?.rank == listEntry?.rank)
        #expect(viewModel.userStanding?.rankedEntry?.isTied == listEntry?.isTied)
    }

    @Test
    func profileSyncKeepsTheTiedCurrentUsersRankAndTieMarker() async {
        // Refreshing the private self photo must not reset rank or drop the tie marker.
        let cache = LeaderboardSessionCache()

        let viewModel = LeaderboardViewModel(sessionCache: cache)
        viewModel.selectedMetric = .climb
        viewModel.selectedTimeFrame = .weekly

        let stats = [
            makeRemoteStat(userId: "aaa", displayName: "Leader", totalSteps: 9_000),
            makeRemoteStat(userId: "mmm", displayName: "Rival", totalSteps: 5_000),
            makeRemoteStat(userId: "zzz", displayName: "You", totalSteps: 5_000)
        ]
        await cache.setDetailEntries(stats, for: .climb, timeFrame: .weekly)

        await viewModel.loadLeaderboard(userId: "zzz")
        viewModel.updateCurrentUserProfile(
            userId: "zzz",
            photoURL: URL(string: "https://example.com/avatar.jpg")
        )

        let listEntry = viewModel.leaderboardEntries.first { $0.userId == "zzz" }
        let moderatedListEntry = listEntry.map {
            CrossUserIdentityAdapter.leaderboardEntry(
                $0,
                blockedUserIds: [],
                isBlockListHydrated: true
            )
        }
        let moderatedUserEntry = viewModel.userStanding?.rankedEntry.map {
            CrossUserIdentityAdapter.leaderboardEntry(
                $0,
                blockedUserIds: [],
                isBlockListHydrated: true
            )
        }
        #expect(moderatedListEntry?.identity.displayName == "You")
        #expect(
            moderatedListEntry?.identity.photoURL ==
                URL(string: "https://example.com/avatar.jpg")
        )
        #expect(listEntry?.rank == 2)
        #expect(listEntry?.isTied == true)
        #expect(listEntry?.isCurrentUser == true)
        #expect(viewModel.userStanding?.rankedEntry?.rank == listEntry?.rank)
        #expect(viewModel.userStanding?.rankedEntry?.isTied == listEntry?.isTied)
        #expect(moderatedUserEntry?.identity.displayName == "You")
    }

    @Test
    func profileSyncLeavesTheSessionCachePopulated() async {
        // Cached remote stats carry published public identity; "You" and the private
        // photo are resolved at build time, so a profile sync must not force a refetch.
        let cache = LeaderboardSessionCache()

        let viewModel = LeaderboardViewModel(sessionCache: cache)
        viewModel.selectedMetric = .climb
        viewModel.selectedTimeFrame = .weekly

        let stats = [makeRemoteStat(userId: "zzz", displayName: "Climber")]
        await cache.setDetailEntries(stats, for: .climb, timeFrame: .weekly)

        await viewModel.loadLeaderboard(userId: "zzz")
        viewModel.updateCurrentUserProfile(
            userId: "zzz",
            photoURL: URL(string: "https://example.com/avatar.jpg")
        )
        await Task.yield()

        #expect(await cache.detailEntries(for: .climb, timeFrame: .weekly)?.count == 1)
    }

    @Test
    func tiedTopStepTotalsBothRankFirst() async {
        let cache = LeaderboardSessionCache()

        let viewModel = LeaderboardViewModel(sessionCache: cache)
        viewModel.selectedMetric = .climb
        viewModel.selectedTimeFrame = .weekly

        let stats = [
            makeRemoteStat(userId: "aaa", displayName: "Tied A", totalSteps: 9_000),
            makeRemoteStat(userId: "bbb", displayName: "Tied B", totalSteps: 9_000),
            makeRemoteStat(userId: "ccc", displayName: "Third", totalSteps: 1_000)
        ]
        await cache.setDetailEntries(stats, for: .climb, timeFrame: .weekly)

        await viewModel.loadLeaderboard(userId: "aaa")

        #expect(viewModel.leaderboardEntries.map(\.rank) == [1, 1, 3])
        #expect(viewModel.leaderboardEntries.map(\.isTied) == [true, true, false])
    }

    @Test
    func untiedBoardFlagsNobodyAsTied() async {
        let cache = LeaderboardSessionCache()

        let viewModel = LeaderboardViewModel(sessionCache: cache)
        viewModel.selectedMetric = .climb
        viewModel.selectedTimeFrame = .weekly

        let stats = [
            makeRemoteStat(userId: "aaa", displayName: "First", totalSteps: 9_000),
            makeRemoteStat(userId: "bbb", displayName: "Second", totalSteps: 5_000),
            makeRemoteStat(userId: "ccc", displayName: "Third", totalSteps: 1_000)
        ]
        await cache.setDetailEntries(stats, for: .climb, timeFrame: .weekly)

        await viewModel.loadLeaderboard(userId: "aaa")

        #expect(viewModel.leaderboardEntries.map(\.rank) == [1, 2, 3])
        #expect(viewModel.leaderboardEntries.allSatisfy { $0.isTied == false })
    }

    /// The captain's weekly screenshot: one climber on the board, the podium showing
    /// places 2 and 3 unclaimed, and the pinned row underneath claiming place 2 on zero
    /// steps.
    ///
    /// The pinned row used to take `leaderboardEntries.count + 1`. That is a positional
    /// rank, and `CompetitionRanking` is the only thing allowed to produce a rank - so the
    /// two surfaces disagreed by construction. A climber with nothing logged this period
    /// holds no rank at all.
    @Test
    func aClimberWithNoActivityThisPeriodHoldsNoRank() async throws {
        let cache = LeaderboardSessionCache()
        // Unique per case: the shared LeaderboardService keeps whichever context was
        // configured last, so a userId reused by another case would find these local stats.
        let userId = "unranked-\(UUID().uuidString)"
        let modelContext = try makeModelContext()
        let service = LeaderboardService()

        let viewModel = LeaderboardViewModel(sessionCache: cache, service: service)
        viewModel.selectedMetric = .climb
        viewModel.selectedTimeFrame = .weekly
        viewModel.configure(userId: userId, modelContext: modelContext)

        // No workouts at all: every current period rebuilds to zero.
        try service.rebuildCurrentStats(for: userId, workouts: [])

        let stats = [makeRemoteStat(userId: "aaa", displayName: "Leader", totalSteps: 48_000)]
        await cache.setDetailEntries(stats, for: .climb, timeFrame: .weekly)

        await viewModel.loadLeaderboard(userId: userId)

        // The board itself is unchanged: the leader still stands alone at rank 1.
        #expect(viewModel.leaderboardEntries.map(\.userId) == ["aaa"])
        #expect(viewModel.leaderboardEntries.map(\.rank) == [1])

        // The pinned row reports zero steps and, critically, no rank.
        #expect(viewModel.userStanding == .unranked(value: 0, formattedValue: "0"))
        #expect(viewModel.userStanding?.rankedEntry == nil)
    }

    /// The same climber, once they have climbed, is ranked normally - the unranked state
    /// must not swallow a legitimate entrant.
    @Test
    func aClimberWithActivityThisPeriodIsRankedAgainstTheBoard() async throws {
        let cache = LeaderboardSessionCache()
        let userId = "ranked-\(UUID().uuidString)"
        let modelContext = try makeModelContext()
        let service = LeaderboardService()

        let viewModel = LeaderboardViewModel(sessionCache: cache, service: service)
        viewModel.selectedMetric = .climb
        viewModel.selectedTimeFrame = .weekly
        viewModel.configure(userId: userId, modelContext: modelContext)

        let now = Date()
        let workout = Workout(
            name: "Workout",
            date: now,
            duration: 1_800,
            steps: 2_000,
            floors: 125,
            stepsPerFloor: 16,
            source: .manual
        )
        workout.markPendingRemoteUpsert(ownerUserId: userId, modifiedAt: now)
        modelContext.insert(workout)
        try modelContext.save()
        try service.rebuildCurrentStats(for: userId, workouts: [workout])

        let stats = [makeRemoteStat(userId: "aaa", displayName: "Leader", totalSteps: 48_000)]
        await cache.setDetailEntries(stats, for: .climb, timeFrame: .weekly)

        await viewModel.loadLeaderboard(userId: userId)

        #expect(viewModel.userStanding?.rankedEntry?.rank == 2)
        #expect(viewModel.userStanding?.rankedEntry?.value == 2_000)
        #expect(viewModel.leaderboardEntries.map(\.rank) == [1, 2])
    }

    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            LeaderboardStats.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeRemoteStat(
        userId: String,
        displayName: String,
        totalDuration: Double = 1_800,
        totalSteps: Int = 1_200
    ) -> FirestoreLeaderboardStats {
        let period = LeaderboardTimeFrame.weekly.currentPeriod(referenceDate: utcDate(year: 2026, month: 4, day: 10))
        let aggregate = LeaderboardAggregate(totalSteps: totalSteps, totalFloors: 75, totalWorkouts: 2, totalDuration: totalDuration)

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
