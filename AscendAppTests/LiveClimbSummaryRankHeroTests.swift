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

    /// The frozen basis still names itself when the summary *is* the moment - it
    /// just says so in the present tense.
    @Test
    func freshCompletionUsesThePresentTenseFrozenCopy() {
        let hero = Hero.make(
            isClimbContext: true,
            moment: .freshCompletion,
            standings: [Hero.Standing(rank: 1, total: 1, basis: .atCompletion)],
            sync: publishedSync(),
            copy: Hero.Copy()
        )

        #expect(hero.detail == "RANK YOU JUST EARNED")
    }

    @Test
    func theMomentOnlyChangesTheFrozenBasis() {
        let current = Hero.make(
            isClimbContext: true,
            moment: .freshCompletion,
            standings: [Hero.Standing(rank: 9, total: 40, basis: .current)],
            sync: publishedSync(),
            copy: Hero.Copy()
        )
        let session = Hero.make(
            isClimbContext: false,
            moment: .freshCompletion,
            standings: [Hero.Standing(rank: 9, total: 40, basis: .liveSession)],
            sync: publishedSync(),
            copy: Hero.Copy(completedDetailOverride: "ROUTINE COMPLETE")
        )

        #expect(current.detail == "CURRENT LEADERBOARD RANK")
        #expect(session.detail == "ROUTINE COMPLETE")
    }

    @Test
    func summariesAreRetrospectiveUnlessTheCallerSaysOtherwise() {
        let hero = Hero.make(
            isClimbContext: true,
            standings: [Hero.Standing(rank: 1, total: 1, basis: .atCompletion)],
            sync: publishedSync(),
            copy: Hero.Copy()
        )

        #expect(hero.detail == "RANK WHEN YOU FINISHED")
    }

    // MARK: - In-session standings

    /// `ActiveRoutineViewModel` and `LiveClimbSessionViewModel` report a rank
    /// measured against their own bucket-windowed race population. The hero can't
    /// characterise that population, so it must not claim a leaderboard basis for
    /// it - it states the session finished, exactly as it did before.
    @Test
    func inSessionStandingKeepsTheNeutralCompletedCopy() {
        let routine = Hero.make(
            isClimbContext: false,
            standings: [Hero.Standing(rank: 3, total: 18, basis: .liveSession)],
            sync: publishedSync(),
            copy: Hero.Copy(
                labelOverride: "ROUTINE RANK",
                completedDetailOverride: "ROUTINE COMPLETE"
            )
        )
        let justClimb = Hero.make(
            isClimbContext: false,
            standings: [Hero.Standing(rank: 3, total: 18, basis: .liveSession)],
            sync: publishedSync(),
            copy: Hero.Copy()
        )

        #expect(routine.value == "3rd")
        #expect(routine.total == 18)
        #expect(routine.detail == "ROUTINE COMPLETE")
        #expect(justClimb.detail == "WORKOUT COMPLETE")
        #expect(justClimb.detail != "CURRENT LEADERBOARD RANK")
    }

    // MARK: - Source precedence

    /// A landmark climb trusts the frozen server sources ahead of any recomputed
    /// one, and the sync store's own mirror ahead of the publish status it
    /// mirrors. Whichever slot wins supplies the denominator too.
    @Test
    func climbPrefersTheFrozenSourcesInOrder() {
        let sources = Hero.Sources(
            session: Hero.Reading(rank: 7, total: 7),
            syncedSnapshot: Hero.Reading(rank: 1, total: 1),
            publishStatus: Hero.Reading(rank: 2, total: 2),
            fetchedSnapshot: Hero.Reading(rank: 3, total: 3),
            computed: Hero.Reading(rank: 29, total: 50)
        )

        let standings = Hero.standings(isClimbContext: true, sources: sources)
            .compactMap { $0 }

        #expect(standings.map(\.rank) == [1, 2, 3, 29])
        #expect(standings.map(\.total) == [1, 2, 3, 50])
        #expect(standings.map(\.basis) == [.atCompletion, .atCompletion, .atCompletion, .current])
    }

    @Test
    func climbIgnoresTheInSessionReadingEntirely() {
        let standings = Hero.standings(
            isClimbContext: true,
            sources: Hero.Sources(session: Hero.Reading(rank: 7, total: 7))
        )

        #expect(standings.compactMap { $0 }.isEmpty)
    }

    /// The publish status is a mirror of the same server doc as the snapshot, so
    /// it only speaks when the snapshot is absent - never the other way round.
    @Test
    func publishStatusOutranksTheFetchedSnapshot() {
        let standings = Hero.standings(
            isClimbContext: true,
            sources: Hero.Sources(
                publishStatus: Hero.Reading(rank: 2, total: 2),
                fetchedSnapshot: Hero.Reading(rank: 3, total: 3)
            )
        )

        #expect(standings.compactMap { $0 }.first?.rank == 2)
    }

    /// Non-climb surfaces keep the order they shipped with: the session's own
    /// figure first, so a routine is never left with no number at all.
    @Test
    func nonClimbSurfacesLeadWithTheirSessionStanding() {
        let sources = Hero.Sources(
            session: Hero.Reading(rank: 4, total: 12),
            syncedSnapshot: Hero.Reading(rank: 1, total: 1),
            publishStatus: Hero.Reading(rank: 2, total: 2),
            fetchedSnapshot: Hero.Reading(rank: 6, total: 30),
            computed: Hero.Reading(rank: 8, total: 40)
        )

        let standings = Hero.standings(isClimbContext: false, sources: sources)
            .compactMap { $0 }

        #expect(standings.map(\.rank) == [4, 6, 8])
        #expect(standings.map(\.basis) == [.liveSession, .atCompletion, .current])
    }

    @Test
    func aReadingWithoutARankProducesNoCandidate() {
        let standings = Hero.standings(
            isClimbContext: false,
            sources: Hero.Sources(
                session: Hero.Reading(rank: nil, total: 12),
                computed: Hero.Reading(rank: 8, total: 40)
            )
        )

        #expect(standings.compactMap { $0 }.map(\.rank) == [8])
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

    /// The unranked overrides are `nil` when the caller has no opinion, so no
    /// caller has to hand a sentinel string back in to keep the default
    /// behaviour. A surface that still tracks a ranking gets the pending copy.
    @Test
    func absentOverridesFollowWhetherTheSurfaceTracksARanking() {
        let tracking = Hero.make(
            isClimbContext: true,
            standings: [],
            sync: Hero.SyncState(
                phase: nil,
                showsPendingRanking: true,
                hasRankContext: true,
                didFinishRankLoad: false
            ),
            copy: Hero.Copy()
        )
        let untracked = Hero.make(
            isClimbContext: true,
            standings: [],
            sync: Hero.SyncState(
                phase: nil,
                showsPendingRanking: false,
                hasRankContext: true,
                didFinishRankLoad: true
            ),
            copy: Hero.Copy()
        )

        #expect(tracking.value == "Checking")
        #expect(tracking.detail == "LOOKING FOR YOUR RANK")
        #expect(untracked.value == "Complete")
        #expect(untracked.detail == "LIVE CLIMB COMPLETE")
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
