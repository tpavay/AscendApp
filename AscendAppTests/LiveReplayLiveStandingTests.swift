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

    /// First of one cannot fall, so it is not a result - the same rule that
    /// keeps `1ST OF 1 CLIMBER` off every board. A first run here states
    /// nothing rather than a hollow ordinal, on the panel and the Lock Screen.
    @Test
    func aFirstEverClimbOnAnEmptyBoardStatesNoPlacingAtAll() {
        #expect(LiveReplayPersonalPlacing.counted(publishedAttempts: 0, ahead: 0) == nil)

        let standing = LiveReplayLiveStanding.resolve(
            field: nil,
            ownClimbs: LiveReplayPersonalPlacing.counted(publishedAttempts: 0, ahead: 0),
            isSoleClimber: true
        )

        #expect(!standing.showsLeaderboardRank)
        #expect(standing.ownClimbs == nil)
        #expect(standing.field == nil)
    }

    @Test
    func aRepeatClimbIsPlacedAmongEveryRunIncludingItself() {
        let placing = LiveReplayPersonalPlacing.counted(publishedAttempts: 4, ahead: 1)

        #expect(placing == LiveReplayPersonalPlacing(placing: 2, total: 5))
        #expect(placing?.fieldLabel == "OF YOUR 5 CLIMBS")
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
    func aPlacingNamesTheFieldItCounted() {
        #expect(LiveReplayPersonalPlacing(placing: 2, total: 2).fieldLabel == "OF YOUR 2 CLIMBS")
        #expect(LiveReplayPersonalPlacing(placing: 3, total: 4).fieldLabel == "OF YOUR 4 CLIMBS")
    }

    // MARK: - One failed read never costs the other answer

    /// The ghost correction and the placing are separate reads answering
    /// separate numbers, so a placing that could not be counted must not drag
    /// the corrected rank down with it. Sharing one failure path put the
    /// captain's original contradiction back: his live row drawn `#2` over a
    /// `1 CLIMBER` field line, off one failed count.
    @Test
    func aFailedPlacingReadStillLeavesTheCorrectedRankStanding() {
        // The ghost was read and subtracted, so he is the whole field of one.
        // The placing was not, so no ordinal is stated - but nothing on this
        // board seats him behind himself either.
        let window = window(totalClimbers: 1)
        let standing = LiveReplayLiveStanding.resolve(
            field: LiveReplayFieldSize(population: .climbers, count: 1),
            ownClimbs: window.ownClimbs,
            isSoleClimber: window.isSoleClimber
        )

        #expect(window.currentUserRank == 1)
        #expect(!standing.showsLeaderboardRank)
        #expect(standing.ownClimbs == nil)
        #expect(standing.field == nil)
    }

    @Test
    func aFailedGhostReadStillLeavesThePlacingStanding() {
        let placing = LiveReplayPersonalPlacing(placing: 2, total: 5)
        let standing = LiveReplayLiveStanding.resolve(
            field: LiveReplayFieldSize(population: .climbers, count: 27),
            ownClimbs: placing,
            isSoleClimber: false
        )

        #expect(standing.ownClimbs == placing)
        #expect(standing.field?.label == "27 CLIMBERS")
    }

    /// Each read reports under its own code and its own once-per-session budget,
    /// so one failing can neither be mistaken for the other nor silence it.
    @Test
    func theGhostAndPlacingReadsReportSeparately() {
        var diagnostics = LiveReplayFinishedRowDiagnostics()
        let ghostReported = diagnostics.shouldReport(.ownGhost)
        let placingReported = diagnostics.shouldReport(.ownClimbPlacing)
        let ghostReportedTwice = diagnostics.shouldReport(.ownGhost)

        #expect(ghostReported)
        #expect(placingReported)
        #expect(!ghostReportedTwice)
        #expect(LiveReplayFinishedRowRead.ownGhost.rawValue
            != LiveReplayFinishedRowRead.ownClimbPlacing.rawValue)
    }

    // MARK: - The Live Activity states the same thing the panel does

    @Test
    func aRacingLockScreenStatesBothNumbersAndNamesBothPopulations() {
        let state = activityState(rank: 2, rankTotal: 27, ownClimbs: (2, 5), board: .racing)

        #expect(state.standingTitle == "Rank")
        #expect(state.standingDetailLabel == "#2 of 27 climbers")
        #expect(state.standingSecondaryLabel == "2nd of your 5 climbs")
    }

    @Test
    func theCompactIslandNeverShowsAnOrdinalWithoutANoun() {
        // The caption carries the noun and not the count. It renders at 7pt in
        // roughly 44 points of Dynamic Island, so a caption that only fits by
        // scaling is not fitting - and the value line above already holds the
        // figure, which is what leaves the ordinal labelled rather than bare.
        let racing = activityState(rank: 2, rankTotal: 27, ownClimbs: (2, 5), board: .racing)
        #expect(racing.standingValue == "#2")
        #expect(racing.standingCaption == "climbers")

        let alone = activityState(rank: nil, rankTotal: 1, ownClimbs: (2, 2), board: .alone)
        #expect(alone.standingValue == "2nd")
        #expect(alone.standingCaption == "your climbs")

        let nobodyElse = activityState(rank: nil, rankTotal: 1, ownClimbs: nil, board: .alone)
        #expect(nobodyElse.standingCaption == "nobody else")

        #expect(racing.standingCaption.count <= "your climbs".count)
        #expect(alone.standingCaption.count <= "your climbs".count)
        #expect(nobodyElse.standingCaption.count <= "your climbs".count)
    }

    @Test
    func aLockScreenAloneOnTheTowerStatesOnlyTheClimbersOwnClimbs() {
        let state = activityState(rank: nil, rankTotal: 1, ownClimbs: (2, 2), board: .alone)

        #expect(state.standingTitle == "Your climbs")
        #expect(state.standingDetailLabel == "2nd of your 2 climbs")
        // The same statement must not appear twice on one surface.
        #expect(state.standingSecondaryLabel == nil)
    }

    /// A Live Activity started by the previous binary is still on the Lock
    /// Screen when the app updates, and its stored state predates the own-climbs
    /// field. A state that fails to decode is one `activities` omits and the
    /// manager can never end, so the old shape has to keep reading.
    @Test
    func aLiveActivityStateWrittenBeforeOwnClimbsExistedStillDecodes() throws {
        let legacy = Data("""
        {"steps":497,"rank":2,"rankTotal":27,"durationSeconds":350,"progress":0.9,"status":"recording","updatedAt":787957195}
        """.utf8)

        let state = try JSONDecoder().decode(
            LiveClimbActivityAttributes.ContentState.self,
            from: legacy
        )

        #expect(state.ownClimbs == nil)
        #expect(state.board == nil)
        #expect(state.standingDetailLabel == "#2 of 27 climbers")
        #expect(state.standingSecondaryLabel == nil)
    }

    /// The same old shape with no rank was a rank the old binary could not
    /// resolve, and it must keep reading as one: a legacy state carries no
    /// board, and a missing board never promotes `--` into "nobody else".
    @Test
    func aLegacyStateWithNoRankStillReadsAsUnresolved() throws {
        let legacy = Data("""
        {"steps":12,"rank":null,"rankTotal":0,"durationSeconds":9,"progress":0.02,"status":"recording","updatedAt":787957195}
        """.utf8)

        let state = try JSONDecoder().decode(
            LiveClimbActivityAttributes.ContentState.self,
            from: legacy
        )

        #expect(state.standing == .unresolved)
        #expect(state.standingValue == "--")
        #expect(state.standingCaption == "rank")
    }

    // MARK: - Three states, and no glyph shared between them

    /// `--` means one thing: a rank that could not be resolved. A first-ever
    /// climber on a board nobody else has finished has no rank to resolve and
    /// nothing has failed, so they render neither an ordinal nor that glyph -
    /// the caption states the condition instead, on every surface. The
    /// captions are asserted beside the values because the defect this pins was
    /// a true value under a false caption, which a value-only check cannot see.
    @Test
    func aResolvedRankRendersTheOrdinalUnderItsPopulation() {
        let state = activityState(rank: 4, rankTotal: 27, ownClimbs: nil, board: .racing)

        #expect(state.standing == .rank(4))
        #expect(state.standingValue == "#4")
        #expect(state.standingCaption == "climbers")
        #expect(state.standingTitle == "Rank")
        #expect(state.standingDetailLabel == "#4 of 27 climbers")
        #expect(state.standingSecondaryLabel == nil)
    }

    @Test
    func aRankThatCouldNotBeResolvedRendersThePlaceholderUnderRank() {
        let state = activityState(rank: nil, rankTotal: 27, ownClimbs: nil, board: .racing)

        #expect(state.standing == .unresolved)
        #expect(state.standingValue == "--")
        #expect(state.standingCaption == "rank")
        #expect(state.standingTitle == "Rank")
        #expect(state.standingDetailLabel == "--")
        #expect(state.standingSecondaryLabel == nil)
    }

    @Test
    func aFirstEverClimberNobodyElseHasRacedRendersNeitherAnOrdinalNorThePlaceholder() {
        let state = activityState(rank: nil, rankTotal: 1, ownClimbs: nil, board: .alone)

        #expect(state.standing == .nobodyElse)
        #expect(state.standingValue == nil)
        #expect(state.standingCaption == "nobody else")
        #expect(state.standingTitle == "Field")
        #expect(state.standingDetailLabel == nil)
        #expect(state.standingSecondaryLabel == "Nobody else has finished")
    }

    /// A board that proves nobody else has finished never shows a leaderboard
    /// rank, whatever number arrived with it: `#1 of 1 climber` is the number
    /// the rank model forbids, and the Lock Screen may not draw it either.
    @Test
    func aRankArrivingOnAnAloneBoardIsNotDrawn() {
        let firstClimb = activityState(rank: 1, rankTotal: 1, ownClimbs: nil, board: .alone)
        #expect(firstClimb.standing == .nobodyElse)
        #expect(firstClimb.standingValue == nil)

        let repeatClimb = activityState(rank: 1, rankTotal: 1, ownClimbs: (2, 2), board: .alone)
        #expect(repeatClimb.standing == .ownClimbs(.init(placing: 2, total: 2)))
        #expect(repeatClimb.standingValue == "2nd")
        #expect(repeatClimb.standingCaption == "your climbs")
    }

    @Test
    func aFieldOfOneIsNamedInTheSingular() {
        let state = activityState(rank: 1, rankTotal: 1, ownClimbs: (1, 1), board: .racing)

        #expect(state.standingDetailLabel == "#1 of 1 climber")
        #expect(state.standingSecondaryLabel == "1st of your 1 climb")
    }

    private func activityState(
        rank: Int?,
        rankTotal: Int,
        ownClimbs: (placing: Int, total: Int)?,
        board: LiveClimbActivityAttributes.ContentState.Board?
    ) -> LiveClimbActivityAttributes.ContentState {
        LiveClimbActivityAttributes.ContentState(
            steps: 497,
            rank: rank,
            rankTotal: rankTotal,
            ownClimbs: ownClimbs.map { .init(placing: $0.placing, total: $0.total) },
            board: board,
            durationSeconds: 350,
            progress: 0.9,
            status: .recording,
            climbPhotoURLString: nil,
            updatedAt: Date(timeIntervalSince1970: 1_787_957_195)
        )
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
