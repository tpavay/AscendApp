import Foundation
import Testing
@testable import AscendApp

/// The frozen-rank rule: once the server has ranked a completed workout, both the position and the
/// denominator are settled for that workout forever, are stored on device, and are never fetched
/// again. Live surfaces are deliberately outside this and keep re-reading the server.
struct CompletedClimbRankFreezeTests {
    private static let context = LiveReplayLeaderboardContext.liveClimb(
        climbId: "burj-khalifa",
        targetSteps: 4_554
    )

    /// Returns the suite name too: every test removes its own persistent domain on the way out, so
    /// a run leaves no defaults plists behind.
    private static func store(
        _ name: String = #function
    ) -> (FrozenCompletionRankStore, UserDefaults, String) {
        let suiteName = "FrozenCompletionRankStoreTests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (FrozenCompletionRankStore(defaults: defaults), defaults, suiteName)
    }

    private static func snapshot(
        workoutId: String = "workout-a",
        rank: Int = 21,
        completedCount: Int = 64
    ) -> LiveReplayCompletionRankSnapshot {
        LiveReplayCompletionRankSnapshot(
            workoutId: workoutId,
            rank: rank,
            completedCount: completedCount,
            completionDurationSeconds: 2_992,
            rankedAt: Date(timeIntervalSince1970: 1_777_777_600),
            rankingMetric: "completionDurationSeconds",
            tiePolicy: "competition_rank_equal_durations_share_rank"
        )
    }

    @Test
    func frozenRankSurvivesAcrossStoreInstances() {
        let (store, defaults, suiteName) = Self.store()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.freeze(Self.snapshot(), contextKey: Self.context.contextKey)

        let reopened = FrozenCompletionRankStore(defaults: defaults)
        let restored = reopened.snapshot(
            contextKey: Self.context.contextKey,
            workoutId: "workout-a"
        )

        #expect(restored?.rank == 21)
        #expect(restored?.completedCount == 64)
    }

    @Test
    func aLaterServerReadNeverMovesAnAlreadyFrozenRank() {
        let (store, defaults, suiteName) = Self.store()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.freeze(Self.snapshot(rank: 21, completedCount: 64), contextKey: Self.context.contextKey)
        let returned = store.freeze(
            Self.snapshot(rank: 34, completedCount: 91),
            contextKey: Self.context.contextKey
        )

        #expect(returned.rank == 21)
        #expect(returned.completedCount == 64)
        #expect(
            store.snapshot(contextKey: Self.context.contextKey, workoutId: "workout-a")?.rank == 21
        )
    }

    @Test
    func theSameWorkoutFreezesIndependentlyPerLeaderboard() {
        let (store, defaults, suiteName) = Self.store()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let routineContext = LiveReplayLeaderboardContext.routineTemplate(
            templateId: "pyramid",
            targetSteps: 2_000
        )

        store.freeze(Self.snapshot(rank: 21), contextKey: Self.context.contextKey)

        #expect(
            store.snapshot(contextKey: routineContext.contextKey, workoutId: "workout-a") == nil
        )
    }

    @Test
    func theServerSnapshotIsFetchedOnceAndReusedOnEveryLaterVisit() async {
        let repository = CountingCompletionSnapshotRepository(
            snapshot: Self.snapshot(rank: 21, completedCount: 64)
        )
        let (persistence, defaults, suiteName) = Self.store()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = await CompletedClimbRankService(
            leaderboardService: LiveReplayLeaderboardService(repository: repository),
            store: persistence
        )

        let first = await service.resolveFrozenRank(context: Self.context, workoutId: "workout-a")
        let second = await service.resolveFrozenRank(context: Self.context, workoutId: "workout-a")
        let reopened = await service.frozenRank(context: Self.context, workoutId: "workout-a")

        #expect(first?.rank == 21)
        #expect(second?.rank == 21)
        #expect(reopened?.rank == 21)
        #expect(await repository.fetchCount == 1)
    }

    /// Freezing is scoped to finished results. A race in progress has no settled answer, so the
    /// live window keeps re-reading the server on every bucket even for a context whose completed
    /// rank is already frozen on this device.
    @Test
    func freezingACompletedRankDoesNotFreezeTheLiveLeaderboard() async throws {
        let repository = CountingCompletionSnapshotRepository(
            snapshot: Self.snapshot(rank: 21, completedCount: 64)
        )
        let (persistence, defaults, suiteName) = Self.store()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = LiveReplayLeaderboardService(repository: repository, minFetchInterval: 0)
        let rankService = await CompletedClimbRankService(
            leaderboardService: service,
            store: persistence
        )

        _ = await rankService.resolveFrozenRank(context: Self.context, workoutId: "workout-a")

        for bucket in 0..<3 {
            _ = try await service.refreshIfNeeded(
                context: Self.context,
                elapsedSeconds: bucket * Self.context.bucketIntervalSeconds,
                currentSteps: bucket * 100,
                force: false
            )
        }

        #expect(await repository.fetchWindowCount == 3)
        #expect(await repository.fetchCount == 1)
    }

    @Test
    func aWorkoutTheServerHasNotRankedIsNotFrozenAtAll() async {
        let repository = CountingCompletionSnapshotRepository(snapshot: nil)
        let (persistence, defaults, suiteName) = Self.store()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = await CompletedClimbRankService(
            leaderboardService: LiveReplayLeaderboardService(repository: repository),
            store: persistence
        )

        let resolved = await service.resolveFrozenRank(context: Self.context, workoutId: "workout-a")

        #expect(resolved == nil)
        #expect(await service.frozenRank(context: Self.context, workoutId: "workout-a") == nil)
    }
}

private actor CountingCompletionSnapshotRepository: LiveReplayLeaderboardRepository {
    private(set) var fetchCount = 0
    private(set) var fetchWindowCount = 0
    private let stored: LiveReplayCompletionRankSnapshot?

    init(snapshot: LiveReplayCompletionRankSnapshot?) {
        self.stored = snapshot
    }

    func fetchSummary(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayLeaderboardSummary {
        .empty
    }

    func fetchCompletionRank(
        context: LiveReplayLeaderboardContext,
        completionDurationSeconds: TimeInterval,
        finalSteps: Int
    ) async throws -> LiveReplayCompletionRank {
        LiveReplayCompletionRank(rank: 99, completedCount: 99, updatedAt: nil)
    }

    func fetchCompletionRankSnapshot(
        context: LiveReplayLeaderboardContext,
        workoutId: String
    ) async throws -> LiveReplayCompletionRankSnapshot? {
        fetchCount += 1
        return stored
    }

    func fetchPublishStatus(
        workoutId: String
    ) async throws -> LiveReplayPublishStatus? {
        nil
    }

    func fetchCurrentUserBestCompletion(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayCurrentUserCompletion? {
        nil
    }

    func fetchCurrentUserFinisherStatus(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayFinisherStatus? {
        nil
    }

    func fetchCompletionLeaderboard(
        context: LiveReplayLeaderboardContext,
        limit: Int,
        cursor: LiveReplayCompletionLeaderboardCursor?,
        forceRefresh: Bool
    ) async throws -> LiveReplayCompletionLeaderboard {
        .empty
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
            fetchedAt: Date(timeIntervalSince1970: 1_777_777_700),
            rows: [],
            currentUserRank: nil,
            totalClimbers: 0
        )
    }
}
