import Foundation
import Testing
@testable import AscendApp

/// The rank hero shows either the standing frozen when the attempt published or a
/// standing recomputed against today's rows. Those measure different populations
/// and legitimately disagree - a first finisher stays "1st of 1" while the climb
/// detail counts every finisher since - so the hero has to name which one it is
/// and must never pair one source's rank with another source's denominator.
///
/// It also never puts a status word where a rank goes. The slot holds a rank, a
/// loading treatment, or nothing at all.
struct LiveClimbSummaryRankHeroTests {
    typealias Hero = LiveClimbSummaryRankHero

    /// Captain-reproduced on CN Tower, 2026-07-31: staging held a frozen snapshot
    /// while the climb detail counted 50 published completions. The hero read
    /// "1st of 12 / LIVE CLIMB COMPLETE", which invites the reader to compare it
    /// with 50.
    ///
    /// The field here is deliberately a real one. A frozen standing over a field
    /// of *one* no longer renders a rank at all - see
    /// `LiveClimbSummaryHeroGoverningRuleTests`.
    @Test
    func frozenStandingNamesItselfInsteadOfClaimingTheSessionCompleted() throws {
        let hero = try #require(Hero.make(
            isClimbContext: true,
            standings: [
                Hero.Standing(rank: 1, total: 12, basis: .atCompletion),
                Hero.Standing(rank: 37, total: 50, basis: .current)
            ],
            sync: publishedSync(),
            copy: Hero.Copy()
        ))

        #expect(hero.value == .rank(1))
        #expect(hero.total == 12)
        #expect(hero.detail == "RANK WHEN YOU FINISHED")
        #expect(hero.detail != "LIVE CLIMB COMPLETE")
        #expect(hero.detail != "CURRENT LEADERBOARD RANK")
    }

    @Test
    func frozenStandingKeepsItsOwnDenominator() throws {
        let hero = try #require(Hero.make(
            isClimbContext: true,
            standings: [
                Hero.Standing(rank: 1, total: 12, basis: .atCompletion),
                Hero.Standing(rank: 1, total: 50, basis: .current)
            ],
            sync: publishedSync(),
            copy: Hero.Copy()
        ))

        #expect(hero.standing?.basis == .atCompletion)
        #expect(hero.total == 12)
    }

    /// The captain's rule: 21st of 64 stays 21st of 64. However many climbers
    /// finish afterwards, a recomputed standing never displaces the frozen one.
    @Test
    func todaysStandingNeverDisplacesTheFrozenOne() throws {
        let hero = try #require(Hero.make(
            isClimbContext: true,
            standings: [
                Hero.Standing(rank: 21, total: 64, basis: .atCompletion),
                Hero.Standing(rank: 34, total: 91, basis: .current)
            ],
            sync: publishedSync(),
            copy: Hero.Copy()
        ))

        #expect(hero.value == .rank(21))
        #expect(hero.total == 64)
        #expect(hero.detail == "RANK WHEN YOU FINISHED")
    }

    @Test
    func recomputedStandingIsLabelledAsCurrent() throws {
        let hero = try #require(Hero.make(
            isClimbContext: true,
            standings: [
                nil,
                Hero.Standing(rank: 21, total: 64, basis: .current)
            ],
            sync: publishedSync(),
            copy: Hero.Copy()
        ))

        #expect(hero.value == .rank(21))
        #expect(hero.total == 64)
        #expect(hero.detail == "CURRENT LEADERBOARD RANK")
    }

    /// The noun follows the number that is on screen, not the board it sits on.
    /// An open Just Climb freezes its stamp over completed attempts and
    /// recomputes over climbers, so one context type answers with both nouns
    /// depending on which standing won precedence.
    @Test
    func theFieldNounFollowsTheBasisOnShow() throws {
        let frozen = try #require(Hero.make(
            isClimbContext: false,
            standings: [Hero.Standing(rank: 13, total: 41, basis: .atCompletion)],
            sync: publishedSync(),
            copy: Hero.Copy()
        ))
        let recomputed = try #require(Hero.make(
            isClimbContext: false,
            standings: [Hero.Standing(rank: 6, total: 16, basis: .current)],
            sync: publishedSync(),
            copy: Hero.Copy()
        ))

        #expect(frozen.fieldPopulation(on: .justClimb) == .completions)
        #expect(recomputed.fieldPopulation(on: .justClimb) == .climbers)
    }

    /// Load-bearing, not cosmetic. The captain accepted a Just Climb summary
    /// counting climbers while Climb Detail lists every completion *because* the
    /// rank card says CLIMBERS out loud - that noun is what disambiguates the two
    /// totals, so it may not change without reopening the decision. Fails if
    /// `recomputedFieldPopulation` is ever tidied back into deriving from
    /// `collapsesRepeatFinishers`, which would silently make these boards say
    /// COMPLETIONS over a climber count.
    @Test(arguments: [
        LiveReplayLeaderboardContextType.justClimb,
        LiveReplayLeaderboardContextType.routine
    ])
    func aRecomputedStandingOnAnAttemptBoardNamesClimbers(
        type: LiveReplayLeaderboardContextType
    ) throws {
        let recomputed = try #require(Hero.make(
            isClimbContext: false,
            standings: [Hero.Standing(rank: 6, total: 16, basis: .current)],
            sync: publishedSync(),
            copy: Hero.Copy()
        ))

        #expect(type.collapsesRepeatFinishers == false)
        #expect(recomputed.fieldPopulation(on: type) == .climbers)
    }

    @Test
    func aCollapsingBoardNamesClimbersOnEitherBasis() throws {
        let frozen = try #require(Hero.make(
            isClimbContext: true,
            standings: [Hero.Standing(rank: 2, total: 2, basis: .atCompletion)],
            sync: publishedSync(),
            copy: Hero.Copy()
        ))
        let recomputed = try #require(Hero.make(
            isClimbContext: true,
            standings: [Hero.Standing(rank: 2, total: 2, basis: .current)],
            sync: publishedSync(),
            copy: Hero.Copy()
        ))

        #expect(frozen.fieldPopulation(on: .liveClimb) == .climbers)
        #expect(recomputed.fieldPopulation(on: .liveClimb) == .climbers)
    }

    @Test
    func labelOverrideSurvivesButDetailStillNamesTheBasis() throws {
        let hero = try #require(Hero.make(
            isClimbContext: false,
            standings: [Hero.Standing(rank: 4, total: 12, basis: .atCompletion)],
            sync: publishedSync(),
            copy: Hero.Copy(labelOverride: "ROUTINE RANK")
        ))

        #expect(hero.label == "ROUTINE RANK")
        #expect(hero.detail == "RANK WHEN YOU FINISHED")
    }

    /// An ordinary leaderboard standing gets no label row: the field line under
    /// the ordinal already says what the position was measured on, and a generic
    /// "CLIMB RANK" over it only repeats the ordinal in words.
    @Test
    func noLabelWithoutACallerOverride() throws {
        let climbHero = try #require(Hero.make(
            isClimbContext: true,
            standings: [],
            sync: publishedSync(),
            copy: Hero.Copy()
        ))
        let globalHero = try #require(Hero.make(
            isClimbContext: false,
            standings: [],
            sync: publishedSync(),
            copy: Hero.Copy()
        ))

        #expect(climbHero.label == nil)
        #expect(globalHero.label == nil)
    }

    @Test
    func absentOrZeroDenominatorRendersNothing() throws {
        let missing = try #require(Hero.make(
            isClimbContext: true,
            standings: [Hero.Standing(rank: 3, total: nil, basis: .atCompletion)],
            sync: publishedSync(),
            copy: Hero.Copy()
        ))
        let zero = try #require(Hero.make(
            isClimbContext: true,
            standings: [Hero.Standing(rank: 3, total: 0, basis: .current)],
            sync: publishedSync(),
            copy: Hero.Copy()
        ))

        #expect(missing.value == .rank(3))
        #expect(missing.total == nil)
        #expect(zero.total == nil)
    }

    @Test
    func rankIsOnlyBuiltFromANonNilPosition() {
        #expect(Hero.Standing(rank: nil, total: 50, basis: .current) == nil)
    }

    // MARK: - The frozen basis

    /// The frozen basis reads the same the instant a climb ends as it does a
    /// month later, because both tenses describe the same number: the rank that
    /// climb's own time earned on the day it landed. The completion-moment
    /// variant said "RANK YOU JUST EARNED" and bought nothing over this, so it
    /// went along with the `Moment` branch that existed only to choose it.
    @Test
    func theFrozenBasisReadsTheSameInBothMoments() throws {
        let hero = try #require(Hero.make(
            isClimbContext: true,
            standings: [Hero.Standing(rank: 4, total: 12, basis: .atCompletion)],
            sync: publishedSync(),
            copy: Hero.Copy()
        ))

        #expect(hero.detail == "RANK WHEN YOU FINISHED")
        #expect(hero.detail != "RANK YOU JUST EARNED")
    }

    @Test
    func theOtherBasesNameTheirOwnPopulation() throws {
        let current = try #require(Hero.make(
            isClimbContext: true,
            standings: [Hero.Standing(rank: 9, total: 40, basis: .current)],
            sync: publishedSync(),
            copy: Hero.Copy()
        ))
        let session = try #require(Hero.make(
            isClimbContext: false,
            standings: [Hero.Standing(rank: 9, total: 40, basis: .liveSession)],
            sync: publishedSync(),
            copy: Hero.Copy(completedDetailOverride: "ROUTINE COMPLETE")
        ))

        #expect(current.detail == "CURRENT LEADERBOARD RANK")
        #expect(session.detail == "ROUTINE COMPLETE")
    }

    // MARK: - In-session standings

    /// `ActiveRoutineViewModel` and `LiveClimbSessionViewModel` report a rank
    /// measured against their own bucket-windowed race population. The hero can't
    /// characterise that population, so it must not claim a leaderboard basis for
    /// it - it states the session finished, exactly as it did before.
    @Test
    func inSessionStandingKeepsTheNeutralCompletedCopy() throws {
        let routine = try #require(Hero.make(
            isClimbContext: false,
            standings: [Hero.Standing(rank: 3, total: 18, basis: .liveSession)],
            sync: publishedSync(),
            copy: Hero.Copy(
                labelOverride: "ROUTINE RANK",
                completedDetailOverride: "ROUTINE COMPLETE"
            )
        ))
        let justClimb = try #require(Hero.make(
            isClimbContext: false,
            standings: [Hero.Standing(rank: 3, total: 18, basis: .liveSession)],
            sync: publishedSync(),
            copy: Hero.Copy()
        ))

        #expect(routine.value == .rank(3))
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
            callerSupplied: Hero.Standing(rank: 7, total: 7, basis: .liveSession),
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
    func climbIgnoresTheCallerSuppliedStandingEntirely() {
        let standings = Hero.standings(
            isClimbContext: true,
            sources: Hero.Sources(
                callerSupplied: Hero.Standing(rank: 7, total: 7, basis: .liveSession)
            )
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

    /// Non-climb surfaces keep the order they shipped with: the caller's own
    /// figure first, so a routine is never left with no number at all.
    @Test
    func nonClimbSurfacesLeadWithTheCallerSuppliedStanding() {
        let sources = Hero.Sources(
            callerSupplied: Hero.Standing(rank: 4, total: 12, basis: .liveSession),
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

    /// The caller-supplied slot carries whatever basis the presenting surface
    /// declared. `LiveClimbSessionView` and `ActiveRoutineView` hand in a
    /// race-window standing; `WorkoutDetailView` hands in a rank it just
    /// recomputed. The same slot must render each one's own copy.
    @Test
    func theCallerSuppliedSlotKeepsWhicheverBasisItWasGiven() throws {
        func detail(for basis: Hero.Basis) throws -> String {
            let standings = Hero.standings(
                isClimbContext: false,
                sources: Hero.Sources(
                    callerSupplied: Hero.Standing(rank: 4, total: 12, basis: basis)
                )
            )

            return try #require(Hero.make(
                isClimbContext: false,
                standings: standings,
                sync: publishedSync(),
                copy: Hero.Copy(completedDetailOverride: "ROUTINE COMPLETE")
            ))
            .detail
        }

        #expect(try detail(for: .liveSession) == "ROUTINE COMPLETE")
        #expect(try detail(for: .current) == "CURRENT LEADERBOARD RANK")
    }

    @Test
    func aReadingWithoutARankProducesNoCandidate() {
        let standings = Hero.standings(
            isClimbContext: false,
            sources: Hero.Sources(
                callerSupplied: Hero.Standing(rank: nil, total: 12, basis: .liveSession),
                computed: Hero.Reading(rank: 8, total: 40)
            )
        )

        #expect(standings.compactMap { $0 }.map(\.rank) == [8])
    }

    // MARK: - Unranked states

    /// The Burj Khalifa defect: the value slot read "Complete" while the real rank
    /// was still on its way, so the wait looked like a stalled load. A rank in
    /// flight now loads, and the detail line says the wait is a lookup.
    @Test
    func aRankInFlightLoadsItsValueAndNamesTheWait() throws {
        let hero = try #require(Hero.make(
            isClimbContext: true,
            standings: [],
            sync: Hero.SyncState(
                phase: .pending,
                hasRankContext: true,
                rankResolution: .resolving
            ),
            copy: Hero.Copy()
        ))

        #expect(hero.value == .loading)
        #expect(hero.label == nil)
        #expect(hero.detail == "LOOKING FOR YOUR RANK")
    }

    @Test
    func aSettledResultWithNoRankShowsNoValueAndExplainsItselfInTheDetailLine() throws {
        let hero = try #require(Hero.make(
            isClimbContext: true,
            standings: [],
            sync: Hero.SyncState(
                phase: .published,
                hasRankContext: true,
                rankResolution: .settled
            ),
            copy: Hero.Copy()
        ))

        #expect(hero.value == .unranked)
        #expect(hero.detail == "CHECK LEADERBOARD LATER")
    }

    /// The state a summary is in for the frame before its lookup starts. Reading
    /// "no answer yet" as "no rank" flashed a terminal card that then jumped to a
    /// skeleton or a rank - the same stalled-load impression, one frame earlier.
    @Test
    func aLookupThatHasNotRunYetLoadsInsteadOfReadingAsSettled() throws {
        for phase: LiveClimbPublicResultPhase? in [nil, .pending, .published] {
            let hero = try #require(Hero.make(
                isClimbContext: true,
                standings: [],
                sync: Hero.SyncState(
                    phase: phase,
                    hasRankContext: true,
                    rankResolution: .notStarted
                ),
                copy: Hero.Copy()
            ))

            #expect(hero.value == .loading)
            #expect(hero.detail == "LOOKING FOR YOUR RANK")
            #expect(hero.detail != "CHECK LEADERBOARD LATER")
        }
    }

    struct SyncPhaseCopyCase: Sendable {
        let phase: LiveClimbPublicResultPhase
        let value: Hero.Value
        let detail: String
        let showsRetrySync: Bool
    }

    @Test(arguments: [
        SyncPhaseCopyCase(
            phase: .savedOnDevice,
            value: .unranked,
            detail: "RESULT SAVED ON DEVICE",
            showsRetrySync: false
        ),
        SyncPhaseCopyCase(
            phase: .syncFailedRetry,
            value: .unranked,
            detail: "SYNC YOUR RESULT TO RANK",
            showsRetrySync: true
        ),
        // Still publishing is a wait, not a terminal state, so it loads.
        SyncPhaseCopyCase(
            phase: .syncingRanking,
            value: .loading,
            detail: "SYNCING RANKING",
            showsRetrySync: false
        )
    ])
    func syncPhasesKeepTheirOwnCopyWithoutNamingThemselvesInTheRankSlot(
        testCase: SyncPhaseCopyCase
    ) throws {
        let hero = try #require(Hero.make(
            isClimbContext: true,
            standings: [],
            sync: Hero.SyncState(
                phase: testCase.phase,
                hasRankContext: true,
                rankResolution: .settled
            ),
            copy: Hero.Copy()
        ))

        #expect(hero.value == testCase.value)
        #expect(hero.detail == testCase.detail)
        #expect(hero.showsRetrySync == testCase.showsRetrySync)
    }

    /// The invariant behind the whole card: no combination of states may put text
    /// in the slot where a rank goes.
    @Test
    func noUnrankedStateEverPutsAStatusWordWhereARankGoes() {
        let phases: [LiveClimbPublicResultPhase?] = [
            nil, .pending, .published, .savedOnDevice, .syncFailedRetry, .syncingRanking
        ]

        for phase in phases {
            for resolution in [Hero.RankResolution.notStarted, .resolving, .settled] {
                for isClimbContext in [true, false] {
                    guard let hero = Hero.make(
                        isClimbContext: isClimbContext,
                        standings: [],
                        sync: Hero.SyncState(
                            phase: phase,
                            hasRankContext: true,
                            rankResolution: resolution
                        ),
                        copy: Hero.Copy()
                    ) else {
                        continue
                    }

                    if case .rank = hero.value {
                        Issue.record("An unranked state produced a rank for phase \(String(describing: phase))")
                    }
                }
            }
        }
    }

    /// Without a leaderboard context there is no population to rank against, so
    /// there is no hero at all. The achievement row below already states that the
    /// session finished; a card that only says "Complete" adds nothing and reads
    /// as a rank that failed to load.
    @Test
    func noRankContextRendersNoHeroAtAll() {
        for isClimbContext in [true, false] {
            #expect(
                Hero.make(
                    isClimbContext: isClimbContext,
                    standings: [Hero.Standing(rank: 3, total: 9, basis: .current)],
                    sync: Hero.SyncState(
                        phase: nil,
                        hasRankContext: false,
                        rankResolution: .settled
                    ),
                    copy: Hero.Copy()
                ) == nil
            )
        }
    }

    /// A routine session that forfeited credit ranks nowhere, so it renders no
    /// hero rather than putting "Incomplete" where a rank goes.
    @Test
    func aForfeitedRoutineSessionRendersNoHero() {
        let forfeited = RoutineCompletionSummaryPresentation(
            stopReason: .skipped,
            hasRoutineLeaderboard: true
        )

        #expect(forfeited.ranksOnLeaderboard == false)
        #expect(
            Hero.make(
                isClimbContext: false,
                standings: [],
                sync: Hero.SyncState(
                    phase: nil,
                    hasRankContext: forfeited.ranksOnLeaderboard,
                    rankResolution: .settled
                ),
                copy: Hero.Copy(labelOverride: "ROUTINE RANK")
            ) == nil
        )
    }

    private func publishedSync() -> Hero.SyncState {
        Hero.SyncState(
            phase: .published,
            hasRankContext: true,
            rankResolution: .settled
        )
    }
}
