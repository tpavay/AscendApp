import Foundation
import Testing
@testable import AscendApp

/// The rank hero shows either the standing frozen when the attempt published or a
/// standing recomputed against today's rows. Those measure different populations
/// and legitimately disagree - a first finisher stays "1st of 1" while the climb
/// detail counts every finisher since - so the hero has to name which one it is
/// and must never pair one source's rank with another source's denominator.
struct LiveClimbSummaryRankHeroTests {
    typealias Hero = LiveClimbSummaryRankHero

    /// Captain-reproduced on CN Tower, 2026-07-31: staging held a frozen snapshot
    /// of rank 1 / completedCount 1 while the climb detail counted 50 published
    /// completions. The hero read "1st of 1 / LIVE CLIMB COMPLETE", which invites
    /// the reader to compare it with 50.
    @Test
    func frozenStandingNamesItselfInsteadOfClaimingTheSessionCompleted() {
        let hero = Hero.make(
            isClimbContext: true,
            standings: [
                Hero.Standing(rank: 1, total: 1, basis: .atCompletion),
                Hero.Standing(rank: 37, total: 50, basis: .current)
            ],
            sync: publishedSync(),
            copy: Hero.Copy()
        )

        #expect(hero.value == "1st")
        #expect(hero.total == 1)
        #expect(hero.detail == "RANK WHEN YOU FINISHED")
        #expect(hero.detail != "LIVE CLIMB COMPLETE")
        #expect(hero.detail != "CURRENT LEADERBOARD RANK")
    }

    @Test
    func frozenStandingKeepsItsOwnDenominator() {
        let hero = Hero.make(
            isClimbContext: true,
            standings: [
                Hero.Standing(rank: 1, total: 1, basis: .atCompletion),
                Hero.Standing(rank: 1, total: 50, basis: .current)
            ],
            sync: publishedSync(),
            copy: Hero.Copy()
        )

        #expect(hero.standing?.basis == .atCompletion)
        #expect(hero.total == 1)
    }

    @Test
    func recomputedStandingIsLabelledAsCurrent() {
        let hero = Hero.make(
            isClimbContext: true,
            standings: [
                nil,
                Hero.Standing(rank: 21, total: 64, basis: .current)
            ],
            sync: publishedSync(),
            copy: Hero.Copy()
        )

        #expect(hero.value == "21st")
        #expect(hero.total == 64)
        #expect(hero.detail == "CURRENT LEADERBOARD RANK")
    }

    @Test
    func labelOverrideSurvivesButDetailStillNamesTheBasis() {
        let hero = Hero.make(
            isClimbContext: false,
            standings: [Hero.Standing(rank: 4, total: 12, basis: .atCompletion)],
            sync: publishedSync(),
            copy: Hero.Copy(
                labelOverride: "ROUTINE RANK",
                completedDetailOverride: "ROUTINE COMPLETE"
            )
        )

        #expect(hero.label == "ROUTINE RANK")
        #expect(hero.detail == "RANK WHEN YOU FINISHED")
    }

    @Test
    func defaultLabelFollowsTheContext() {
        let climbHero = Hero.make(
            isClimbContext: true,
            standings: [],
            sync: publishedSync(),
            copy: Hero.Copy()
        )
        let globalHero = Hero.make(
            isClimbContext: false,
            standings: [],
            sync: publishedSync(),
            copy: Hero.Copy()
        )

        #expect(climbHero.label == "CLIMB RANK")
        #expect(globalHero.label == "GLOBAL RANK")
    }

    @Test
    func absentOrZeroDenominatorRendersNothing() {
        let missing = Hero.make(
            isClimbContext: true,
            standings: [Hero.Standing(rank: 3, total: nil, basis: .atCompletion)],
            sync: publishedSync(),
            copy: Hero.Copy()
        )
        let zero = Hero.make(
            isClimbContext: true,
            standings: [Hero.Standing(rank: 3, total: 0, basis: .current)],
            sync: publishedSync(),
            copy: Hero.Copy()
        )

        #expect(missing.value == "3rd")
        #expect(missing.total == nil)
        #expect(zero.total == nil)
    }

    @Test
    func rankIsOnlyBuiltFromANonNilPosition() {
        #expect(Hero.Standing(rank: nil, total: 50, basis: .current) == nil)
    }

    // MARK: - Unranked states

    @Test
    func pendingRankLoadShowsCheckingWhileAContextExists() {
        let hero = Hero.make(
            isClimbContext: true,
            standings: [],
            sync: Hero.SyncState(
                phase: .pending,
                showsPendingRanking: true,
                hasRankContext: true,
                didFinishRankLoad: false
            ),
            copy: Hero.Copy()
        )

        #expect(hero.value == "Checking")
        #expect(hero.detail == "LOOKING FOR YOUR RANK")
    }

    @Test
    func finishedLoadWithoutARankFallsBackToUnavailable() {
        let hero = Hero.make(
            isClimbContext: true,
            standings: [],
            sync: Hero.SyncState(
                phase: .published,
                showsPendingRanking: true,
                hasRankContext: true,
                didFinishRankLoad: true
            ),
            copy: Hero.Copy()
        )

        #expect(hero.value == "Unavailable")
        #expect(hero.detail == "CHECK LEADERBOARD LATER")
    }

    struct SyncPhaseCopyCase: Sendable {
        let phase: LiveClimbPublicResultPhase
        let value: String
        let detail: String
    }

    @Test(arguments: [
        SyncPhaseCopyCase(
            phase: .savedOnDevice,
            value: "Saved",
            detail: "RESULT SAVED ON DEVICE"
        ),
        SyncPhaseCopyCase(
            phase: .syncFailedRetry,
            value: "Sync failed",
            detail: "SYNC YOUR RESULT TO RANK"
        ),
        SyncPhaseCopyCase(
            phase: .syncingRanking,
            value: "Syncing",
            detail: "SYNCING RANKING"
        )
    ])
    func syncPhasesKeepTheirOwnCopy(testCase: SyncPhaseCopyCase) {
        let hero = Hero.make(
            isClimbContext: true,
            standings: [],
            sync: Hero.SyncState(
                phase: testCase.phase,
                showsPendingRanking: true,
                hasRankContext: true,
                didFinishRankLoad: false
            ),
            copy: Hero.Copy()
        )

        #expect(hero.value == testCase.value)
        #expect(hero.detail == testCase.detail)
    }

    /// Pre-existing precedence, pinned here so a later change to it is deliberate:
    /// once the rank load has finished with nothing to show, "Unavailable" wins
    /// over the sync-phase copy even when the result is only saved on device.
    @Test
    func finishedLoadOutranksSyncPhaseCopy() {
        let hero = Hero.make(
            isClimbContext: true,
            standings: [],
            sync: Hero.SyncState(
                phase: .savedOnDevice,
                showsPendingRanking: true,
                hasRankContext: true,
                didFinishRankLoad: true
            ),
            copy: Hero.Copy()
        )

        #expect(hero.value == "Unavailable")
        #expect(hero.detail == "CHECK LEADERBOARD LATER")
    }

    /// Without a leaderboard context there is no population to rank against, so
    /// the hero states the session finished rather than implying a standing.
    @Test
    func noRankContextStatesCompletionInstead() {
        let climbHero = Hero.make(
            isClimbContext: true,
            standings: [],
            sync: Hero.SyncState(
                phase: nil,
                showsPendingRanking: false,
                hasRankContext: false,
                didFinishRankLoad: true
            ),
            copy: Hero.Copy()
        )
        let workoutHero = Hero.make(
            isClimbContext: false,
            standings: [],
            sync: Hero.SyncState(
                phase: nil,
                showsPendingRanking: false,
                hasRankContext: false,
                didFinishRankLoad: true
            ),
            copy: Hero.Copy()
        )

        #expect(climbHero.value == "Complete")
        #expect(climbHero.detail == "LIVE CLIMB COMPLETE")
        #expect(workoutHero.value == "Complete")
        #expect(workoutHero.detail == "WORKOUT COMPLETE")
    }

    @Test
    func completedDetailOverrideStillWinsWhenThereIsNoRank() {
        let hero = Hero.make(
            isClimbContext: false,
            standings: [],
            sync: Hero.SyncState(
                phase: nil,
                showsPendingRanking: false,
                hasRankContext: false,
                didFinishRankLoad: true
            ),
            copy: Hero.Copy(completedDetailOverride: "ROUTINE COMPLETE")
        )

        #expect(hero.detail == "ROUTINE COMPLETE")
    }

    @Test
    func callerSuppliedUnrankedCopyIsHonoured() {
        let hero = Hero.make(
            isClimbContext: false,
            standings: [],
            sync: Hero.SyncState(
                phase: nil,
                showsPendingRanking: false,
                hasRankContext: false,
                didFinishRankLoad: true
            ),
            copy: Hero.Copy(
                unrankedValue: "Forfeited",
                unrankedDetail: "INTERVALS SKIPPED"
            )
        )

        #expect(hero.value == "Forfeited")
        #expect(hero.detail == "INTERVALS SKIPPED")
    }

    private func publishedSync() -> Hero.SyncState {
        Hero.SyncState(
            phase: .published,
            showsPendingRanking: true,
            hasRankContext: true,
            didFinishRankLoad: true
        )
    }
}
