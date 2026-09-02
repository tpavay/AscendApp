import Foundation
import Testing
@testable import AscendApp

/// The finish-card hero rule the captain locked on 2026-09-01.
///
/// > The leaderboard rank takes the hero whenever a real field exists. When the
/// > climber is the only one on the tower, the hero states their placing among
/// > their own climbs. When both are true the leaderboard rank leads and the
/// > personal placing drops to the achievement row.
///
/// Recorded across `rank-when-alone`, `solo-repeat-finish-card`,
/// `rival-repeat-finish-card`, `first-ascent-finish-card`,
/// `first-ascent-line-copy`, `marker-label-fade-and-ordinal-accent` and
/// `finish-card-label-not-accent` in
/// `data/ascend-climb-ranking-ghost-design/decisions/`.
///
/// The shipped defect these replace: a climber alone on a tower saw
/// `1st of 1 CLIMBER` over `RANK YOU JUST EARNED` **including when the repeat was
/// slower**, because the ordinal was invariant across every possible performance.
struct LiveClimbSummaryHeroGoverningRuleTests {
    typealias Hero = LiveClimbSummaryRankHero

    // MARK: - Alone on the tower

    /// The parked finding, `slower-repeat-still-freezes-first-place`, asserted
    /// directly: the server still freezes a standing of 1 over a field of 1, and
    /// the card must not render it as a rank.
    @Test
    func aSoloSlowerRepeatNeverRendersALeaderboardRank() throws {
        let hero = try #require(Hero.make(
            isClimbContext: true,
            moment: .freshCompletion,
            standings: [Hero.Standing(rank: 1, total: 1, basis: .atCompletion)],
            personalPlacing: PersonalClimbPlacing(ordinal: 2, total: 5),
            sync: publishedSync(),
            copy: Hero.Copy()
        ))

        #expect(hero.value == .personalPlacing(PersonalClimbPlacing(ordinal: 2, total: 5)))
        #expect(hero.value != .rank(1))
        #expect(hero.detail == "OF YOUR 5 CLIMBS")
        #expect(hero.detail != Hero.freshAtCompletionDetail)
        #expect(hero.detail != Hero.atCompletionDetail)
    }

    /// The same component covers the improved run. One ordinal states both
    /// outcomes, so there is no separate personal-best hero to keep in sync.
    @Test
    func aSoloPersonalBestUsesTheSameOrdinalRatherThanASecondDesign() throws {
        let hero = try #require(Hero.make(
            isClimbContext: true,
            moment: .freshCompletion,
            standings: [Hero.Standing(rank: 1, total: 1, basis: .atCompletion)],
            personalPlacing: PersonalClimbPlacing(ordinal: 1, total: 5),
            sync: publishedSync(),
            copy: Hero.Copy()
        ))

        #expect(hero.value == .personalPlacing(PersonalClimbPlacing(ordinal: 1, total: 5)))
        #expect(hero.detail == "OF YOUR 5 CLIMBS")
    }

    /// No path through a field of one reaches a rank, whatever the basis, the
    /// moment, or the placing. This is the assertion that would fail if the old
    /// behaviour returned by any route.
    @Test
    func noFieldOfOneOnAClimbCanEverProduceARank() throws {
        for basis in [Hero.Basis.atCompletion, .current] {
            for moment in [Hero.Moment.freshCompletion, .retrospective] {
                for ordinal in 1...4 {
                    let hero = try #require(Hero.make(
                        isClimbContext: true,
                        moment: moment,
                        standings: [Hero.Standing(rank: 1, total: 1, basis: basis)],
                        personalPlacing: PersonalClimbPlacing(ordinal: ordinal, total: 4),
                        sync: publishedSync(),
                        copy: Hero.Copy()
                    ))

                    if case .rank = hero.value {
                        Issue.record("a field of one rendered a leaderboard rank")
                    }
                }
            }
        }
    }

    /// Until the climber's own history has been read there is nothing true to put
    /// in the slot, and the one thing that must never fill it is the rank this
    /// rule exists to remove. So it waits.
    @Test
    func aFieldOfOneWaitsRatherThanFallingBackToTheRank() throws {
        let pending = try #require(Hero.make(
            isClimbContext: true,
            standings: [Hero.Standing(rank: 1, total: 1, basis: .atCompletion)],
            personalPlacing: nil,
            sync: Hero.SyncState(
                phase: .published,
                hasRankContext: true,
                rankResolution: .resolving
            ),
            copy: Hero.Copy()
        ))
        let settled = try #require(Hero.make(
            isClimbContext: true,
            standings: [Hero.Standing(rank: 1, total: 1, basis: .atCompletion)],
            personalPlacing: nil,
            sync: publishedSync(),
            copy: Hero.Copy()
        ))

        #expect(pending.value == .loading)
        #expect(settled.value == .unranked)
        #expect(settled.value != .rank(1))
        // What it waits *to* matters as much: a tower with one climber on it has
        // no leaderboard to send them to.
        #expect(pending.detail == Hero.soloResolvingDetail)
        #expect(settled.detail == Hero.soloUnverifiedDetail)
        #expect(settled.detail != "CHECK LEADERBOARD LATER")
    }

    // MARK: - First Ascent

    /// A first finish with nobody else on the board is the flag, and nothing else:
    /// no rank, no sentence, no date (`first-ascent-line-copy`). It is the one
    /// hero with no number, because every number here expires and a First Ascent
    /// does not.
    @Test
    func aFirstFinishWithNobodyElseOnTheBoardIsTheFlagAndTheClaimAlone() throws {
        let hero = try #require(Hero.make(
            isClimbContext: true,
            moment: .freshCompletion,
            standings: [Hero.Standing(rank: 1, total: 1, basis: .atCompletion)],
            personalPlacing: PersonalClimbPlacing(ordinal: 1, total: 1),
            claimsFirstAscent: true,
            sync: publishedSync(),
            copy: Hero.Copy()
        ))

        #expect(hero.value == .firstAscent)
        #expect(hero.detail == "FIRST ASCENT CLAIMED")
        #expect(hero.detailEmphasis == .prestige)
        #expect(hero.label == nil)
    }

    /// A climber's first finish on a tower others have already climbed is an
    /// ordinary standing, not a claim.
    @Test
    func aFirstFinishBehindOtherClimbersIsARankNotAClaim() throws {
        let hero = try #require(Hero.make(
            isClimbContext: true,
            standings: [Hero.Standing(rank: 12, total: 31, basis: .atCompletion)],
            personalPlacing: PersonalClimbPlacing(ordinal: 1, total: 1),
            claimsFirstAscent: false,
            sync: publishedSync(),
            copy: Hero.Copy()
        ))

        #expect(hero.value == .rank(12))
        #expect(hero.value != .firstAscent)
    }

    /// A First Ascent does not expire.
    ///
    /// The claim used to be read off "this is my only climb here", so reopening
    /// the very summary that earned the flag - `WorkoutDetailView` routes back to
    /// it - retired the gold flag for `4TH OF YOUR 4 CLIMBS` the moment the
    /// climber went back to the tower. The frozen standing never moves and the
    /// claim is resolved from permanent facts, so it renders unchanged.
    @Test
    func aFirstAscentStillRendersAfterTheClimberReturnsToTheTower() throws {
        let hero = try #require(Hero.make(
            isClimbContext: true,
            moment: .retrospective,
            standings: [Hero.Standing(rank: 1, total: 1, basis: .atCompletion)],
            personalPlacing: PersonalClimbPlacing(ordinal: 4, total: 4),
            claimsFirstAscent: true,
            sync: publishedSync(),
            copy: Hero.Copy()
        ))

        #expect(hero.value == .firstAscent)
        #expect(hero.detail == "FIRST ASCENT CLAIMED")
        #expect(hero.detailEmphasis == .prestige)
    }

    /// The other half of the same rule: a repeat that did *not* claim the tower
    /// still reads as a placing among the climber's own climbs, so the flag
    /// cannot start standing in for every solo finish.
    @Test
    func aSoloRepeatThatClaimedNothingIsStillAnOrdinal() throws {
        let hero = try #require(Hero.make(
            isClimbContext: true,
            standings: [Hero.Standing(rank: 1, total: 1, basis: .atCompletion)],
            personalPlacing: PersonalClimbPlacing(ordinal: 2, total: 5),
            claimsFirstAscent: false,
            sync: publishedSync(),
            copy: Hero.Copy()
        ))

        #expect(hero.value == .personalPlacing(PersonalClimbPlacing(ordinal: 2, total: 5)))
        #expect(hero.detail == "OF YOUR 5 CLIMBS")
    }

    // MARK: - A real field of climbers

    /// Two ordinals, two explicitly named fields, no collision: the leaderboard
    /// rank leads and the personal placing is still available for the achievement
    /// row beneath it.
    @Test
    func aRealFieldOfClimbersKeepsTheLeaderboardRankInTheHero() throws {
        let placing = PersonalClimbPlacing(ordinal: 2, total: 5)
        let hero = try #require(Hero.make(
            isClimbContext: true,
            standings: [Hero.Standing(rank: 2, total: 2, basis: .atCompletion)],
            personalPlacing: placing,
            sync: publishedSync(),
            copy: Hero.Copy()
        ))

        #expect(hero.value == .rank(2))
        #expect(hero.total == 2)
        #expect(placing.achievementTitle == "2ND OF YOUR 5 CLIMBS")
    }

    /// A standing with no denominator says nothing about how many climbers
    /// finished. Demoting it on that silence would replace a real rank with a
    /// guess, so the rank stands.
    @Test
    func aStandingWithNoDenominatorKeepsItsRank() throws {
        let hero = try #require(Hero.make(
            isClimbContext: true,
            standings: [Hero.Standing(rank: 3, total: nil, basis: .atCompletion)],
            personalPlacing: PersonalClimbPlacing(ordinal: 2, total: 5),
            sync: publishedSync(),
            copy: Hero.Copy()
        ))

        #expect(hero.value == .rank(3))
    }

    /// The rule is a climb rule. A routine or an open Just Climb has no tower to
    /// have climbed twice, so their heroes are untouched.
    @Test
    func nonClimbSurfacesAreUnaffected() throws {
        let hero = try #require(Hero.make(
            isClimbContext: false,
            standings: [Hero.Standing(rank: 1, total: 1, basis: .liveSession)],
            personalPlacing: PersonalClimbPlacing(ordinal: 2, total: 5),
            sync: publishedSync(),
            copy: Hero.Copy(completedDetailOverride: "ROUTINE COMPLETE")
        ))

        #expect(hero.value == .rank(1))
        #expect(hero.detail == "ROUTINE COMPLETE")
    }

    // MARK: - Colour

    /// The ordinal is the accent in every case; only the First Ascent claim is
    /// gold. The label beneath already names whose field is counted, so a
    /// colour split there would be saying the same thing twice
    /// (`marker-label-fade-and-ordinal-accent`, `finish-card-label-not-accent`).
    @Test
    func onlyTheFirstAscentClaimIsGivenPrestigeEmphasis() throws {
        let personal = try #require(Hero.make(
            isClimbContext: true,
            standings: [Hero.Standing(rank: 1, total: 1, basis: .atCompletion)],
            personalPlacing: PersonalClimbPlacing(ordinal: 2, total: 5),
            sync: publishedSync(),
            copy: Hero.Copy()
        ))
        let ranked = try #require(Hero.make(
            isClimbContext: true,
            standings: [Hero.Standing(rank: 2, total: 9, basis: .atCompletion)],
            personalPlacing: PersonalClimbPlacing(ordinal: 2, total: 5),
            sync: publishedSync(),
            copy: Hero.Copy()
        ))

        #expect(personal.detailEmphasis == .neutral)
        #expect(ranked.detailEmphasis == .neutral)
    }

    private func publishedSync() -> Hero.SyncState {
        Hero.SyncState(
            phase: .published,
            hasRankContext: true,
            rankResolution: .settled
        )
    }
}
