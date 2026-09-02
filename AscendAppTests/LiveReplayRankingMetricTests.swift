import Foundation
import Testing
@testable import AscendApp

/// A climb fixes the step target and races the clock; a routine fixes the clock and
/// races the steps taken inside it. These lock the client half of that split against
/// `rankingMetric` in `functions/src/liveReplayLeaderboard.ts` - if the two disagree,
/// a displayed rank contradicts the rank the server published.
struct LiveReplayRankingMetricTests {
    @Test
    func climbContextsRankOnTheFastestCompletion() {
        #expect(LiveReplayLeaderboardContextType.liveClimb.rankingMetric == .fastestCompletion)
        #expect(LiveReplayLeaderboardContextType.justClimb.rankingMetric == .fastestCompletion)
    }

    /// The server's `ranksOnSteps` is `contextType === "routine_template"` and
    /// nothing else, so a plain `routine` board ranks on the clock there. The
    /// client said steps for both, which was not a difference of opinion: it
    /// queried `bestFinalSteps` on finisher documents that only ever carry
    /// `bestCompletionDurationSeconds`, matched nothing, and read every climber
    /// on the board as first.
    @Test
    func onlyARoutineTemplateBoardRanksOnSteps() {
        #expect(LiveReplayLeaderboardContextType.routineTemplate.rankingMetric == .mostSteps)
        #expect(LiveReplayLeaderboardContextType.routine.rankingMetric == .fastestCompletion)
    }

    /// The client's numerator counts finisher documents through this field, so a
    /// context that names a field the server never writes on that context counts
    /// zero rivals and reports first place to everybody. Pinned per context type
    /// against `finisherBestMetric` in `functions/src/liveReplayLeaderboard.ts`.
    @Test(arguments: LiveReplayLeaderboardContextType.allCases)
    func everyContextQueriesTheFinisherFieldTheServerWrites(
        type: LiveReplayLeaderboardContextType
    ) {
        let expected = type == .routineTemplate
            ? "bestFinalSteps"
            : "bestCompletionDurationSeconds"

        #expect(type.rankingMetric.finisherBestField == expected)
    }

    @Test
    func finisherBestFieldsMatchTheStoredFinisherFields() {
        #expect(
            LiveReplayRankingMetric.fastestCompletion.finisherBestField ==
                "bestCompletionDurationSeconds"
        )
        #expect(LiveReplayRankingMetric.mostSteps.finisherBestField == "bestFinalSteps")
    }

    @Test
    func metricFieldsMatchTheStoredEntryFields() {
        #expect(LiveReplayRankingMetric.fastestCompletion.field == "completionDurationSeconds")
        #expect(LiveReplayRankingMetric.mostSteps.field == "finalSteps")
    }

    @Test
    func onlyStepsRankHighestFirst() {
        #expect(LiveReplayRankingMetric.fastestCompletion.ranksHighestFirst == false)
        #expect(LiveReplayRankingMetric.mostSteps.ranksHighestFirst)
    }

    /// A board that headlines a number it did not rank on reads as broken ordering.
    @Test
    func boardsLeadWithTheNumberTheyRankedOn() {
        #expect(LiveReplayRankingMetric.fastestCompletion.rowEmphasis == .duration)
        #expect(LiveReplayRankingMetric.mostSteps.rowEmphasis == .steps)
    }

    /// Steps are coarse integers, so routine ties are common. The continuation carries
    /// the raw ranking value, and equal values must keep one shared rank across a page
    /// boundary rather than restarting at the next position.
    @Test
    func tiedStepCountsShareOneRankAcrossAPageBoundary() {
        let firstPage = [1_840.0, 1_720.0]
        let firstRanks = CompetitionRanking.ranks(for: firstPage, key: { $0 })
        #expect(firstRanks == [1, 2])

        let cursor = LiveReplayCompletionLeaderboardCursor(
            sortKey: 1_720,
            rowID: "workout-b",
            lastRank: 2,
            rankedCount: 2
        )
        let secondRanks = CompetitionRanking.ranks(
            for: [1_720.0, 1_650.0],
            continuing: cursor.rankingContinuation,
            key: { $0 }
        )

        #expect(secondRanks == [2, 4])
    }
}
