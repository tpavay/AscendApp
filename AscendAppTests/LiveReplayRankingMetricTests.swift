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

    @Test
    func routineContextsRankOnSteps() {
        #expect(LiveReplayLeaderboardContextType.routineTemplate.rankingMetric == .mostSteps)
        #expect(LiveReplayLeaderboardContextType.routine.rankingMetric == .mostSteps)
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
