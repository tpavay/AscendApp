import Foundation
import Testing
@testable import AscendApp

/// Every number a live surface shows is labelled with the population it counted.
///
/// The captain's second St Peter's Basilica climb wore a bare `#1` mid-race with
/// nothing on screen naming what the one counted, and the finish card told him
/// the truth seconds later. These pin the two states that replace it, on the
/// live panel and the Live Activity together, so neither can regress into an
/// unlabelled ordinal.
struct LiveReplayLiveStandingTests {

    // MARK: - Alone on the tower

    @Test
    func aClimberNobodyElseHasRacedGetsNoLeaderboardPlacingAtAll() {
        let standing = LiveReplayLiveStanding.resolve(
            field: LiveReplayFieldSize(population: .climbers, count: 1),
            ownClimbs: LiveReplayPersonalPlacing(placing: 2, total: 2),
            isSoleClimber: true
        )

        #expect(!standing.showsLeaderboardRank)
        // A "1 CLIMBER" line beside an ordinal is the thing being removed, so the
        // field is dropped whole rather than rendered next to nothing.
        #expect(standing.field == nil)
        #expect(standing.ownClimbs?.placing == 2)
        #expect(standing.ownClimbs?.fieldLabel == "OF YOUR 2 CLIMBS")
    }

    @Test
    func aFirstEverClimbOnAnEmptyBoardIsFirstOfOneOfTheirOwn() {
        let standing = LiveReplayLiveStanding.resolve(
            field: nil,
            ownClimbs: .firstClimb,
            isSoleClimber: true
        )

        #expect(!standing.showsLeaderboardRank)
        #expect(standing.ownClimbs?.ordinalText == 1.rankOrdinalText)
        #expect(standing.ownClimbs?.fieldLabel == "OF YOUR 1 CLIMB")
    }

    @Test
    func aSoloBoardThatCouldNotCountTheirClimbsStatesNoOrdinalRatherThanABareOne() {
        // The history read is non-fatal, and losing it must not leave an ordinal
        // with nothing naming what it counted.
        let standing = LiveReplayLiveStanding.resolve(
            field: LiveReplayFieldSize(population: .climbers, count: 1),
            ownClimbs: nil,
            isSoleClimber: true
        )

        #expect(!standing.showsLeaderboardRank)
        #expect(standing.ownClimbs == nil)
        #expect(standing.field == nil)
    }

    // MARK: - A real field

    @Test
    func aBoardWithRivalsStatesBothNumbersAndNamesBothPopulations() {
        let standing = LiveReplayLiveStanding.resolve(
            field: LiveReplayFieldSize(population: .climbers, count: 27),
            ownClimbs: LiveReplayPersonalPlacing(placing: 2, total: 5),
            isSoleClimber: false
        )

        #expect(standing.showsLeaderboardRank)
        #expect(standing.field?.label == "27 CLIMBERS")
        #expect(standing.ownClimbs?.fieldLabel == "OF YOUR 5 CLIMBS")
    }

    @Test
    func aBoardThatCannotCountItsFieldStillRanksAgainstTheRivalsOnIt() {
        // A routine board substantiates no field size. That is not the same
        // statement as "nobody else is here", and reading it as one would strip
        // the leaderboard placing off a board that has rivals.
        let standing = LiveReplayLiveStanding.resolve(
            field: nil,
            ownClimbs: LiveReplayPersonalPlacing(placing: 1, total: 3),
            isSoleClimber: false
        )

        #expect(standing.showsLeaderboardRank)
        #expect(standing.field == nil)
    }

    // MARK: - The window's own answer

    @Test
    func aWindowCountingOneClimberIsTheAloneCase() {
        #expect(window(totalClimbers: 1).isSoleClimber)
        #expect(window(totalClimbers: 0).isSoleClimber)
        #expect(!window(totalClimbers: 2).isSoleClimber)
    }

    @Test
    func aPlacingNamesItsFieldInTheSingularForOneClimb() {
        #expect(LiveReplayPersonalPlacing(placing: 1, total: 1).fieldLabel == "OF YOUR 1 CLIMB")
        #expect(LiveReplayPersonalPlacing(placing: 3, total: 4).fieldLabel == "OF YOUR 4 CLIMBS")
    }

    private func window(totalClimbers: Int) -> LiveReplayLeaderboardWindow {
        LiveReplayLeaderboardWindow(
            context: .liveClimb(
                climbId: "st-peters-basilica",
                targetSteps: 551,
                bucketIntervalSeconds: 10
            ),
            bucketIndex: 35,
            currentSteps: 497,
            fetchedAt: Date(timeIntervalSince1970: 1_787_957_195),
            rows: [],
            currentUserRank: 1,
            totalClimbers: totalClimbers
        )
    }
}
