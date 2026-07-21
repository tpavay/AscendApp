import Foundation
import Testing
@testable import AscendApp

struct LiveReplayLeaderboardServiceTests {
    @Test
    func refreshesOnBucketChangeButRateLimitsSameBucket() async throws {
        let repository = MockLiveReplayLeaderboardRepository()
        let fixedDate = Date(timeIntervalSince1970: 1_777_777_777)
        let service = LiveReplayLeaderboardService(
            repository: repository,
            minFetchInterval: 999,
            now: { fixedDate }
        )
        let context = LiveReplayLeaderboardContext.liveClimb(
            climbId: "pyramid-giza",
            targetSteps: 809
        )

        let firstWindow = try await service.refreshIfNeeded(
            context: context,
            elapsedSeconds: 2,
            currentSteps: 12,
            force: false
        )
        let skippedWindow = try await service.refreshIfNeeded(
            context: context,
            elapsedSeconds: 8,
            currentSteps: 20,
            force: false
        )
        let secondWindow = try await service.refreshIfNeeded(
            context: context,
            elapsedSeconds: 10,
            currentSteps: 25,
            force: false
        )

        #expect(firstWindow?.bucketIndex == 0)
        #expect(skippedWindow == nil)
        #expect(secondWindow?.bucketIndex == 1)
        #expect(await repository.fetchWindowCount == 2)
    }

    @Test
    func refreshesSameBucketAfterMinimumInterval() async throws {
        let repository = MockLiveReplayLeaderboardRepository()
        let clock = MutableDateProvider(Date(timeIntervalSince1970: 1_777_777_777))
        let service = LiveReplayLeaderboardService(
            repository: repository,
            minFetchInterval: 5,
            now: { clock.now() }
        )
        let context = LiveReplayLeaderboardContext.liveClimb(
            climbId: "pyramid-giza",
            targetSteps: 809
        )

        _ = try await service.refreshIfNeeded(
            context: context,
            elapsedSeconds: 2,
            currentSteps: 12,
            force: false
        )
        clock.currentDate.addTimeInterval(4)
        let skippedWindow = try await service.refreshIfNeeded(
            context: context,
            elapsedSeconds: 6,
            currentSteps: 20,
            force: false
        )
        clock.currentDate.addTimeInterval(2)
        let refreshedWindow = try await service.refreshIfNeeded(
            context: context,
            elapsedSeconds: 8,
            currentSteps: 30,
            force: false
        )

        #expect(skippedWindow == nil)
        #expect(refreshedWindow?.bucketIndex == 0)
        #expect(refreshedWindow?.currentSteps == 30)
        #expect(await repository.fetchWindowCount == 2)
    }

    @Test
    func fetchesCurrentUserFinisherStatus() async throws {
        let repository = MockLiveReplayLeaderboardRepository()
        let service = LiveReplayLeaderboardService(repository: repository)
        let context = LiveReplayLeaderboardContext.liveClimb(
            climbId: "pyramid-giza",
            targetSteps: 809
        )

        let status = try await service.fetchCurrentUserFinisherStatus(context: context)

        #expect(status?.globalCompletionOrder == 47)
        #expect(status?.bestCompletionDurationSeconds == 872)
        #expect(await repository.fetchFinisherStatusCount == 1)
    }

    @Test
    func fetchesCurrentUserBestCompletion() async throws {
        let repository = MockLiveReplayLeaderboardRepository()
        let service = LiveReplayLeaderboardService(repository: repository)
        let context = LiveReplayLeaderboardContext.liveClimb(
            climbId: "pyramid-giza",
            targetSteps: 809
        )

        let completion = try await service.fetchCurrentUserBestCompletion(context: context)

        #expect(completion?.rank == 12)
        #expect(completion?.completedCount == 89)
        #expect(completion?.workoutId == "workout-best")
        #expect(await repository.fetchCurrentUserBestCompletionCount == 1)
    }

    @Test
    func fetchesPublishStatus() async throws {
        let repository = MockLiveReplayLeaderboardRepository()
        let service = LiveReplayLeaderboardService(repository: repository)

        let status = try await service.fetchPublishStatus(workoutId: "workout-a")

        #expect(status?.state == .published)
        #expect(status?.rankAtCompletion == 18)
        #expect(status?.completedCountAtCompletion == 62)
        #expect(await repository.fetchPublishStatusCount == 1)
    }

    @Test
    func fetchesCompletionRankSnapshot() async throws {
        let repository = MockLiveReplayLeaderboardRepository()
        let service = LiveReplayLeaderboardService(repository: repository)
        let context = LiveReplayLeaderboardContext.liveClimb(
            climbId: "pyramid-giza",
            targetSteps: 809
        )

        let snapshot = try await service.fetchCompletionRankSnapshot(
            context: context,
            workoutId: "workout-a"
        )

        #expect(snapshot?.rank == 18)
        #expect(snapshot?.completedCount == 62)
        #expect(snapshot?.workoutId == "workout-a")
        #expect(await repository.fetchCompletionRankSnapshotCount == 1)
    }

    @Test
    func cachesCompletionLeaderboardFirstPageWithinTTL() async throws {
        let repository = MockLiveReplayLeaderboardRepository()
        let fixedDate = Date(timeIntervalSince1970: 1_777_777_777)
        let service = LiveReplayLeaderboardService(
            repository: repository,
            completionCacheTTL: 300,
            now: { fixedDate }
        )
        let context = LiveReplayLeaderboardContext.liveClimb(
            climbId: "pyramid-giza",
            targetSteps: 809
        )

        _ = try await service.fetchCompletionLeaderboard(
            context: context,
            limit: 25
        )
        _ = try await service.fetchCompletionLeaderboard(
            context: context,
            limit: 25
        )

        #expect(await repository.fetchCompletionLeaderboardCount == 1)
    }

    @Test
    func forceRefreshBypassesCompletionLeaderboardCache() async throws {
        let repository = MockLiveReplayLeaderboardRepository()
        let fixedDate = Date(timeIntervalSince1970: 1_777_777_777)
        let service = LiveReplayLeaderboardService(
            repository: repository,
            completionCacheTTL: 300,
            now: { fixedDate }
        )
        let context = LiveReplayLeaderboardContext.liveClimb(
            climbId: "pyramid-giza",
            targetSteps: 809
        )

        _ = try await service.fetchCompletionLeaderboard(
            context: context,
            limit: 25
        )
        _ = try await service.fetchCompletionLeaderboard(
            context: context,
            limit: 25,
            cursor: nil,
            forceRefresh: true
        )

        #expect(await repository.fetchCompletionLeaderboardCount == 2)
    }
}

private final class MutableDateProvider: @unchecked Sendable {
    var currentDate: Date

    init(_ currentDate: Date) {
        self.currentDate = currentDate
    }

    func now() -> Date {
        currentDate
    }
}

private actor MockLiveReplayLeaderboardRepository: LiveReplayLeaderboardRepository {
    private(set) var fetchWindowCount = 0
    private(set) var fetchFinisherStatusCount = 0
    private(set) var fetchCurrentUserBestCompletionCount = 0
    private(set) var fetchPublishStatusCount = 0
    private(set) var fetchCompletionRankSnapshotCount = 0
    private(set) var fetchCompletionLeaderboardCount = 0

    func fetchSummary(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayLeaderboardSummary {
        LiveReplayLeaderboardSummary(
            totalClimbers: 247,
            completedCount: 89,
            personalBestDurationSeconds: 872,
            updatedAt: Date(timeIntervalSince1970: 1_777_777_700)
        )
    }

    func fetchCompletionRank(
        context: LiveReplayLeaderboardContext,
        completionDurationSeconds: TimeInterval,
        finalSteps: Int
    ) async throws -> LiveReplayCompletionRank {
        LiveReplayCompletionRank(
            rank: 12,
            completedCount: 89,
            updatedAt: Date(timeIntervalSince1970: 1_777_777_700)
        )
    }

    func fetchCompletionRankSnapshot(
        context: LiveReplayLeaderboardContext,
        workoutId: String
    ) async throws -> LiveReplayCompletionRankSnapshot? {
        fetchCompletionRankSnapshotCount += 1

        return LiveReplayCompletionRankSnapshot(
            workoutId: workoutId,
            rank: 18,
            completedCount: 62,
            completionDurationSeconds: 872,
            rankedAt: Date(timeIntervalSince1970: 1_777_777_650),
            rankingMetric: "completionDurationSeconds",
            tiePolicy: "competition_rank_equal_durations_share_rank"
        )
    }

    func fetchPublishStatus(
        workoutId: String
    ) async throws -> LiveReplayPublishStatus? {
        fetchPublishStatusCount += 1

        return LiveReplayPublishStatus(
            state: .published,
            workoutId: workoutId,
            userId: "user-a",
            contextType: "live_climb",
            contextId: "pyramid-giza",
            rankAtCompletion: 18,
            completedCountAtCompletion: 62,
            finisherOrder: 47,
            lastErrorCode: nil,
            lastErrorMessageSafe: nil,
            updatedAt: Date(timeIntervalSince1970: 1_777_777_700),
            publishedAt: Date(timeIntervalSince1970: 1_777_777_700)
        )
    }

    func fetchCurrentUserBestCompletion(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayCurrentUserCompletion? {
        fetchCurrentUserBestCompletionCount += 1

        return LiveReplayCurrentUserCompletion(
            rank: 12,
            completedCount: 89,
            completionDurationSeconds: 872,
            workoutId: "workout-best",
            updatedAt: Date(timeIntervalSince1970: 1_777_777_700)
        )
    }

    func fetchCurrentUserFinisherStatus(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayFinisherStatus? {
        fetchFinisherStatusCount += 1

        return LiveReplayFinisherStatus(
            globalCompletionOrder: 47,
            firstCompletedAt: Date(timeIntervalSince1970: 1_777_777_600),
            bestCompletionDurationSeconds: 872,
            updatedAt: Date(timeIntervalSince1970: 1_777_777_700)
        )
    }

    func fetchCompletionLeaderboard(
        context: LiveReplayLeaderboardContext,
        limit: Int,
        cursor: LiveReplayCompletionLeaderboardCursor?,
        forceRefresh: Bool
    ) async throws -> LiveReplayCompletionLeaderboard {
        fetchCompletionLeaderboardCount += 1

        return LiveReplayCompletionLeaderboard(
            rows: [
                LiveReplayLeaderboardRow(
                    id: "attempt-a",
                    rank: 1,
                    displayName: "Sarah K.",
                    avatarToken: "SK",
                    photoURL: URL(string: "https://example.com/sarah.jpg"),
                    stepsAtBucket: 0,
                    finalSteps: 809,
                    deltaFromUser: 0,
                    isCurrentUser: false,
                    isPersonalBest: false,
                    completionDurationSeconds: 800
                )
            ],
            completedCount: 89,
            updatedAt: Date(timeIntervalSince1970: 1_777_777_700)
        )
    }

    func fetchWindow(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int,
        currentSteps: Int,
        rowsAhead: Int,
        rowsBehind: Int
    ) async throws -> LiveReplayLeaderboardWindow {
        fetchWindowCount += 1

        return LiveReplayLeaderboardWindow(
            context: context,
            bucketIndex: bucketIndex,
            currentSteps: currentSteps,
            fetchedAt: Date(timeIntervalSince1970: 1_777_777_777),
            rows: [
                LiveReplayLeaderboardRow(
                    id: "attempt-a",
                    rank: 12,
                    displayName: "Sarah K.",
                    avatarToken: "SK",
                    photoURL: URL(string: "https://example.com/sarah.jpg"),
                    stepsAtBucket: currentSteps + 30,
                    finalSteps: currentSteps + 300,
                    deltaFromUser: 30,
                    isCurrentUser: false,
                    isPersonalBest: false,
                    completionDurationSeconds: 800
                )
            ],
            currentUserRank: 13,
            totalClimbers: 247
        )
    }
}

struct LiveReplayLeaderboardWindowTests {
    @Test
    func locallyReordersVisibleRowsWhenCurrentUserPassesCompetitors() {
        let context = LiveReplayLeaderboardContext.liveClimb(
            climbId: "pyramid-giza",
            targetSteps: 809
        )
        let window = LiveReplayLeaderboardWindow(
            context: context,
            bucketIndex: 2,
            currentSteps: 100,
            fetchedAt: Date(timeIntervalSince1970: 1_777_777_777),
            rows: [
                makeRow(id: "ahead-a", rank: 1, stepsAtBucket: 130, deltaFromUser: 30),
                makeRow(id: "ahead-b", rank: 2, stepsAtBucket: 110, deltaFromUser: 10),
                makeRow(id: "behind-a", rank: 4, stepsAtBucket: 90, deltaFromUser: -10)
            ],
            currentUserRank: 3,
            totalClimbers: 10
        )

        let rows = window.locallyRankedRows(
            currentSteps: 115,
            currentElapsedSeconds: 20
        )

        #expect(rows.map(\.id) == ["ahead-a", "current-user", "ahead-b", "behind-a"])
        #expect(rows.map { $0.rank ?? -1 } == [1, 2, 3, 4])
        #expect(rows.first(where: { $0.id == "ahead-b" })?.deltaFromUser == -5)
        #expect(rows.first(where: \.isCurrentUser)?.stepsAtBucket == 115)
    }

    @Test
    func locallyRanksSavedCompetitorsAheadOfCurrentUserOnTies() {
        let context = LiveReplayLeaderboardContext.liveClimb(
            climbId: "pyramid-giza",
            targetSteps: 809
        )
        let window = LiveReplayLeaderboardWindow(
            context: context,
            bucketIndex: 0,
            currentSteps: 0,
            fetchedAt: Date(timeIntervalSince1970: 1_777_777_777),
            rows: [
                makeRow(id: "ahead-a", rank: 88, stepsAtBucket: 0, deltaFromUser: 0),
                makeRow(id: "ahead-b", rank: 89, stepsAtBucket: 0, deltaFromUser: 0)
            ],
            currentUserRank: 90,
            totalClimbers: 90
        )

        let rows = window.locallyRankedRows(
            currentSteps: 0,
            currentElapsedSeconds: 0
        )

        #expect(rows.map(\.id) == ["ahead-a", "ahead-b", "current-user"])
        #expect(rows.map { $0.rank ?? -1 } == [88, 89, 90])
    }

    @Test
    func locallyImprovesRankAfterCurrentUserPassesTiedCompetitors() {
        let context = LiveReplayLeaderboardContext.liveClimb(
            climbId: "pyramid-giza",
            targetSteps: 809
        )
        let window = LiveReplayLeaderboardWindow(
            context: context,
            bucketIndex: 0,
            currentSteps: 0,
            fetchedAt: Date(timeIntervalSince1970: 1_777_777_777),
            rows: [
                makeRow(id: "ahead-a", rank: 1, stepsAtBucket: 0, deltaFromUser: 0),
                makeRow(id: "ahead-b", rank: 2, stepsAtBucket: 0, deltaFromUser: 0)
            ],
            currentUserRank: 3,
            totalClimbers: 3
        )

        let rows = window.locallyRankedRows(
            currentSteps: 1,
            currentElapsedSeconds: 0
        )

        #expect(rows.map(\.id) == ["current-user", "ahead-a", "ahead-b"])
        #expect(rows.map { $0.rank ?? -1 } == [1, 2, 3])
    }

    @Test
    func requestsFreshWindowWhenCurrentUserExhaustsVisibleRows() {
        let context = LiveReplayLeaderboardContext.liveClimb(
            climbId: "pyramid-giza",
            targetSteps: 809
        )
        let window = LiveReplayLeaderboardWindow(
            context: context,
            bucketIndex: 2,
            currentSteps: 100,
            fetchedAt: Date(timeIntervalSince1970: 1_777_777_777),
            rows: [
                makeRow(id: "ahead-a", rank: 3, stepsAtBucket: 130, deltaFromUser: 30),
                makeRow(id: "ahead-b", rank: 4, stepsAtBucket: 110, deltaFromUser: 10),
                makeRow(id: "behind-a", rank: 6, stepsAtBucket: 90, deltaFromUser: -10),
                makeRow(id: "behind-b", rank: 7, stepsAtBucket: 80, deltaFromUser: -20)
            ],
            currentUserRank: 5,
            totalClimbers: 10
        )

        #expect(window.needsFreshWindow(currentSteps: 105, currentElapsedSeconds: 20) == false)
        #expect(window.needsFreshWindow(currentSteps: 135, currentElapsedSeconds: 20) == true)
    }

    @Test
    func requestsFreshWindowWhenCurrentUserReachesTopOfFetchedWindowAtEstimatedFirstRank() {
        let context = LiveReplayLeaderboardContext.liveClimb(
            climbId: "pyramid-giza",
            targetSteps: 809
        )
        let window = LiveReplayLeaderboardWindow(
            context: context,
            bucketIndex: 2,
            currentSteps: 100,
            fetchedAt: Date(timeIntervalSince1970: 1_777_777_777),
            rows: [
                makeRow(id: "ahead-a", rank: 1, stepsAtBucket: 130, deltaFromUser: 30),
                makeRow(id: "ahead-b", rank: 2, stepsAtBucket: 110, deltaFromUser: 10)
            ],
            currentUserRank: 3,
            totalClimbers: 3
        )

        #expect(window.needsFreshWindow(currentSteps: 135, currentElapsedSeconds: 20) == true)
    }

    @Test
    func requestsFreshWindowWhenCurrentUserIsNearTopEdgeOfFetchedWindow() {
        let context = LiveReplayLeaderboardContext.liveClimb(
            climbId: "pyramid-giza",
            targetSteps: 809
        )
        let window = LiveReplayLeaderboardWindow(
            context: context,
            bucketIndex: 2,
            currentSteps: 100,
            fetchedAt: Date(timeIntervalSince1970: 1_777_777_777),
            rows: [
                makeRow(id: "ahead-a", rank: 4, stepsAtBucket: 130, deltaFromUser: 30),
                makeRow(id: "behind-a", rank: 6, stepsAtBucket: 90, deltaFromUser: -10),
                makeRow(id: "behind-b", rank: 7, stepsAtBucket: 80, deltaFromUser: -20)
            ],
            currentUserRank: 5,
            totalClimbers: 10
        )

        #expect(window.needsFreshWindow(currentSteps: 100, currentElapsedSeconds: 20) == true)
    }

    @Test
    func requestsFreshWindowWhenCurrentUserIsNearBottomEdgeOfFetchedWindow() {
        let context = LiveReplayLeaderboardContext.liveClimb(
            climbId: "pyramid-giza",
            targetSteps: 809
        )
        let window = LiveReplayLeaderboardWindow(
            context: context,
            bucketIndex: 2,
            currentSteps: 100,
            fetchedAt: Date(timeIntervalSince1970: 1_777_777_777),
            rows: [
                makeRow(id: "ahead-a", rank: 3, stepsAtBucket: 130, deltaFromUser: 30),
                makeRow(id: "ahead-b", rank: 4, stepsAtBucket: 120, deltaFromUser: 20),
                makeRow(id: "behind-a", rank: 6, stepsAtBucket: 90, deltaFromUser: -10)
            ],
            currentUserRank: 5,
            totalClimbers: 10
        )

        #expect(window.needsFreshWindow(currentSteps: 100, currentElapsedSeconds: 20) == true)
    }

    @Test
    func keepsBufferedWindowWhenCurrentUserStillHasRowsOnBothSides() {
        let context = LiveReplayLeaderboardContext.liveClimb(
            climbId: "pyramid-giza",
            targetSteps: 809
        )
        let window = LiveReplayLeaderboardWindow(
            context: context,
            bucketIndex: 2,
            currentSteps: 100,
            fetchedAt: Date(timeIntervalSince1970: 1_777_777_777),
            rows: [
                makeRow(id: "ahead-a", rank: 2, stepsAtBucket: 150, deltaFromUser: 50),
                makeRow(id: "ahead-b", rank: 3, stepsAtBucket: 140, deltaFromUser: 40),
                makeRow(id: "behind-a", rank: 5, stepsAtBucket: 90, deltaFromUser: -10),
                makeRow(id: "behind-b", rank: 6, stepsAtBucket: 80, deltaFromUser: -20)
            ],
            currentUserRank: 4,
            totalClimbers: 10
        )

        #expect(window.needsFreshWindow(currentSteps: 100, currentElapsedSeconds: 20) == false)
    }

    @Test
    func doesNotRequestFreshWindowWhenCurrentUserWasAlreadyFetchedAtGlobalTop() {
        let context = LiveReplayLeaderboardContext.liveClimb(
            climbId: "pyramid-giza",
            targetSteps: 809
        )
        let window = LiveReplayLeaderboardWindow(
            context: context,
            bucketIndex: 2,
            currentSteps: 140,
            fetchedAt: Date(timeIntervalSince1970: 1_777_777_777),
            rows: [
                makeRow(id: "behind-a", rank: 2, stepsAtBucket: 120, deltaFromUser: -20),
                makeRow(id: "behind-b", rank: 3, stepsAtBucket: 100, deltaFromUser: -40)
            ],
            currentUserRank: 1,
            totalClimbers: 3
        )

        #expect(window.needsFreshWindow(currentSteps: 145, currentElapsedSeconds: 20) == false)
    }

    @Test
    func requestsFreshWindowWhenLocalRankImproves() {
        let context = LiveReplayLeaderboardContext.liveClimb(
            climbId: "pyramid-giza",
            targetSteps: 809
        )
        let window = LiveReplayLeaderboardWindow(
            context: context,
            bucketIndex: 2,
            currentSteps: 100,
            fetchedAt: Date(timeIntervalSince1970: 1_777_777_777),
            rows: [
                makeRow(id: "ahead-a", rank: 3, stepsAtBucket: 130, deltaFromUser: 30),
                makeRow(id: "ahead-b", rank: 4, stepsAtBucket: 110, deltaFromUser: 10),
                makeRow(id: "behind-a", rank: 6, stepsAtBucket: 90, deltaFromUser: -10),
                makeRow(id: "behind-b", rank: 7, stepsAtBucket: 80, deltaFromUser: -20)
            ],
            currentUserRank: 5,
            totalClimbers: 10
        )

        #expect(window.needsFreshWindow(currentSteps: 105, currentElapsedSeconds: 20) == false)
        #expect(window.needsFreshWindow(currentSteps: 115, currentElapsedSeconds: 20) == true)
    }

    @Test
    func locallyWorsensRankWhenFetchedBehindRowsProjectAhead() {
        let context = LiveReplayLeaderboardContext.liveClimb(
            climbId: "pyramid-giza",
            targetSteps: 809
        )
        let window = LiveReplayLeaderboardWindow(
            context: context,
            bucketIndex: 2,
            currentSteps: 100,
            fetchedAt: Date(timeIntervalSince1970: 1_777_777_777),
            rows: [
                makeRow(id: "behind-a", rank: 6, stepsAtBucket: 90, finalSteps: 220, deltaFromUser: -10)
            ],
            currentUserRank: 5,
            totalClimbers: 10
        )

        let rows = window.locallyRankedRows(
            currentSteps: 100,
            currentElapsedSeconds: 40
        )

        #expect(rows.map(\.id) == ["behind-a", "current-user"])
        #expect(rows.first(where: \.isCurrentUser)?.rank == 6)
        #expect(window.needsFreshWindow(currentSteps: 100, currentElapsedSeconds: 40) == true)
    }

    @Test
    func locallyProjectsCompetitorStepsForwardBetweenBackendRefreshes() {
        let row = makeRow(
            id: "ahead-a",
            rank: 1,
            stepsAtBucket: 2,
            finalSteps: 120,
            deltaFromUser: 2
        )

        let projectedRow = row.projected(
            elapsedSeconds: 30,
            bucketElapsedSeconds: 0
        )

        #expect(projectedRow.stepsAtBucket > row.stepsAtBucket)
        #expect(projectedRow.stepsAtBucket <= row.finalSteps)
    }

    private func makeRow(
        id: String,
        rank: Int,
        stepsAtBucket: Int,
        finalSteps: Int? = nil,
        deltaFromUser: Int
    ) -> LiveReplayLeaderboardRow {
        LiveReplayLeaderboardRow(
            id: id,
            rank: rank,
            displayName: "Climber",
            avatarToken: "C",
            photoURL: nil,
            stepsAtBucket: stepsAtBucket,
            finalSteps: finalSteps ?? max(stepsAtBucket, 200),
            deltaFromUser: deltaFromUser,
            isCurrentUser: false,
            isPersonalBest: false,
            completionDurationSeconds: nil
        )
    }
}
