import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Sharing a saved climb has to publish the rank the climber earned.
///
/// The captain's report, reproduced against staging's own numbers: an Empire State Building climb
/// finished in 16:46 over 1,576 steps, ranked 32nd of 85 by the server. Opening its completion
/// summary showed that rank; opening the share sheet from the saved climb offered no rank - because
/// Workout Detail built it with no rank at all.
///
/// The two symptoms have one cause, and these tests prove that rather than assume it: the picker's
/// clusters and the recap card's rank tab both read the single rank pair the composer is
/// constructed with, so restoring that pair restores both, and withholding it drops both cleanly.
@MainActor
struct SavedClimbShareRankTests {
    private static let context = LiveReplayLeaderboardContext.liveClimb(
        climbId: "empire-state-building",
        targetSteps: 1_576
    )
    private static let workoutId = "1181618B-AD09-4B2B-AB93-C53B9188E210"

    // MARK: - The saved path resolves a standing

    /// The frozen standing this device already holds is served without a request, so opening the
    /// composer from a climb whose summary has been read never waits on the network.
    @Test
    func aStoredFrozenStandingReachesTheSavedClimbShareCardWithoutARequest() async {
        let (store, defaults, suiteName) = Self.frozenStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        store.freeze(Self.snapshot(), contextKey: Self.context.contextKey)

        let leaderboard = StubLiveReplayLeaderboardService()
        let service = CompletedClimbRankService(leaderboardService: leaderboard, store: store)

        let standing = await SavedClimbShareStanding.resolve(
            context: Self.context,
            workoutId: Self.workoutId,
            service: service
        )

        #expect(standing == SavedClimbShareStanding(snapshot: Self.snapshot()))
        #expect(standing?.rank == 32)
        #expect(standing?.totalClimbers == 85)
        #expect(leaderboard.completionRankSnapshotFetchCount == 0, "a stored standing was refetched")
    }

    /// A device that has never opened this climb's summary still shares its rank: the one shared
    /// read path fetches the server snapshot once and freezes it.
    @Test
    func aStandingNeverReadOnThisDeviceIsFetchedOnceAndFrozen() async {
        let (store, defaults, suiteName) = Self.frozenStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let leaderboard = StubLiveReplayLeaderboardService()
        leaderboard.completionRankSnapshot = Self.snapshot()
        let service = CompletedClimbRankService(leaderboardService: leaderboard, store: store)

        let first = await SavedClimbShareStanding.resolve(
            context: Self.context,
            workoutId: Self.workoutId,
            service: service
        )
        let second = await SavedClimbShareStanding.resolve(
            context: Self.context,
            workoutId: Self.workoutId,
            service: service
        )

        #expect(first?.rank == 32)
        #expect(second == first, "the second read disagreed with the frozen answer")
        #expect(leaderboard.completionRankSnapshotFetchCount == 1)
        #expect(
            store.snapshot(contextKey: Self.context.contextKey, workoutId: Self.workoutId)?.rank == 32
        )
    }

    /// A workout the server ranks nowhere stays unranked. Nothing is invented locally, and nothing
    /// is frozen, so the share card drops its rank rather than showing a placeholder.
    @Test
    func aClimbTheServerHasNotRankedResolvesToNoStanding() async {
        let (store, defaults, suiteName) = Self.frozenStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let leaderboard = StubLiveReplayLeaderboardService()
        let service = CompletedClimbRankService(leaderboardService: leaderboard, store: store)

        let standing = await SavedClimbShareStanding.resolve(
            context: Self.context,
            workoutId: Self.workoutId,
            service: service
        )

        #expect(standing == nil)
        #expect(store.snapshot(contextKey: Self.context.contextKey, workoutId: Self.workoutId) == nil)
    }

    /// The only standing a share card withholds is one the server never wrote. A snapshot that
    /// exists always carries a usable pair - `LiveReplayCompletionRankSnapshot` clamps both halves
    /// to at least one - so there is no half-populated case for a card to render around.
    @Test
    func onlyAnAbsentSnapshotIsAnAbsentStanding() throws {
        #expect(SavedClimbShareStanding(snapshot: nil) == nil)

        let clamped = try #require(SavedClimbShareStanding(snapshot: Self.snapshot(rank: 0)))
        #expect(clamped.rank == 1)
        #expect(clamped.totalClimbers == 85)
    }

    /// A card publishes; a screen reports. The completion summary keeps showing where the climber
    /// stands right now, and it forwards a rank to the composer only when that rank is the
    /// permanent one - so a climb the server has not ranked yet shares without a rank rather than
    /// printing today's position onto an image that outlives it.
    @Test
    func onlyAFrozenSummaryStandingIsForwardedToTheCard() throws {
        let recomputed = try #require(Self.hero(
            standings: [LiveClimbSummaryRankHero.Standing(rank: 34, total: 91, basis: .current)]
        ))
        #expect(recomputed.value == .rank(34), "the summary stopped showing the current standing")
        let recomputedStanding = try #require(recomputed.standing)
        #expect(recomputedStanding.frozen == nil)

        let session = try #require(
            LiveClimbSummaryRankHero.Standing(rank: 3, total: 8, basis: .liveSession)
        )
        #expect(session.frozen == nil)

        let frozen = try #require(Self.hero(
            standings: [
                LiveClimbSummaryRankHero.Standing(rank: 32, total: 85, basis: .atCompletion),
                LiveClimbSummaryRankHero.Standing(rank: 34, total: 91, basis: .current)
            ]
        ))
        let frozenStanding = try #require(frozen.standing?.frozen)
        #expect(frozenStanding.rank == 32)
        #expect(frozenStanding.renderableTotal == 85)
    }

    // MARK: - What the Share tap hands over

    /// The tap seeds from what this device already holds, so a climb whose standing has been read
    /// once reaches the composer's first frame: no request, and nothing to await.
    @Test
    func aStoredStandingIsSeededSynchronouslyAndWithoutARequest() throws {
        let (store, defaults, suiteName) = Self.frozenStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        store.freeze(Self.snapshot(), contextKey: Self.context.contextKey)

        let leaderboard = StubLiveReplayLeaderboardService()
        let service = CompletedClimbRankService(leaderboardService: leaderboard, store: store)

        let seeded = try #require(SavedClimbShareStanding.stored(
            context: Self.context,
            workoutId: Self.workoutId,
            service: service
        ))

        #expect(seeded.rank == 32)
        #expect(seeded.totalClimbers == 85)
        #expect(leaderboard.completionRankSnapshotFetchCount == 0, "the seed reached the network")
    }

    /// A device that has never read this climb's standing seeds nothing, which is what sends the
    /// composer's own read after it. Nothing is invented locally to fill the gap.
    @Test
    func aStandingThisDeviceHasNeverReadSeedsNothing() {
        let (store, defaults, suiteName) = Self.frozenStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let leaderboard = StubLiveReplayLeaderboardService()
        leaderboard.completionRankSnapshot = Self.snapshot()
        let service = CompletedClimbRankService(leaderboardService: leaderboard, store: store)

        let seeded = SavedClimbShareStanding.stored(
            context: Self.context,
            workoutId: Self.workoutId,
            service: service
        )

        #expect(seeded == nil)
        #expect(leaderboard.completionRankSnapshotFetchCount == 0)
    }

    // MARK: - Fixtures

    private static func hero(
        standings: [LiveClimbSummaryRankHero.Standing?]
    ) -> LiveClimbSummaryRankHero? {
        LiveClimbSummaryRankHero.make(
            isClimbContext: true,
            standings: standings,
            sync: LiveClimbSummaryRankHero.SyncState(
                phase: .published,
                hasRankContext: true,
                rankResolution: .settled
            ),
            copy: LiveClimbSummaryRankHero.Copy()
        )
    }

    private static func frozenStore(
        _ name: String = #function
    ) -> (FrozenCompletionRankStore, UserDefaults, String) {
        let suiteName = "SavedClimbShareRankTests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (FrozenCompletionRankStore(defaults: defaults), defaults, suiteName)
    }

    /// Staging's own `completionSnapshots` document for the climb the captain reported.
    private static func snapshot(
        rank: Int = 32,
        completedCount: Int = 85
    ) -> LiveReplayCompletionRankSnapshot {
        LiveReplayCompletionRankSnapshot(
            workoutId: workoutId,
            rank: rank,
            completedCount: completedCount,
            completionDurationSeconds: 1_006,
            rankedAt: Date(timeIntervalSince1970: 1_787_859_963),
            rankingMetric: "completionDurationSeconds",
            tiePolicy: "competition_rank_equal_durations_share_rank"
        )
    }
}
