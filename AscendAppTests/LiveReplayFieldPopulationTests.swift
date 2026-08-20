import Foundation
import Testing
@testable import AscendApp

/// Two Ascend surfaces count different populations of one climb on purpose: the live
/// race collapses a rival's repeat runs to their best, and the static per-climb board
/// keeps every completion. Both are right, and a climber who reads one then the other
/// will see two totals. These lock the noun each surface states, because an unlabelled
/// field size is what makes that difference read as a defect.
struct LiveReplayFieldPopulationTests {
    /// Mirrors the server allowlist in `functions/src/liveReplayLeaderboard.ts`. A
    /// context that collapses repeats races a field of climbers.
    @Test
    func onlyPerClimbAndPerTemplateContextsCollapseRepeats() {
        #expect(LiveReplayLeaderboardContextType.liveClimb.collapsesRepeatFinishers)
        #expect(LiveReplayLeaderboardContextType.routineTemplate.collapsesRepeatFinishers)
        #expect(LiveReplayLeaderboardContextType.justClimb.collapsesRepeatFinishers == false)
        #expect(LiveReplayLeaderboardContextType.routine.collapsesRepeatFinishers == false)
    }

    /// An open Just Climb session has no target, so it races every completed attempt as
    /// its own opponent. Calling that field "climbers" would overcount nobody and
    /// undercount the runs a climber can actually see.
    @Test
    func populationFollowsWhetherTheContextCollapsesRepeats() {
        #expect(LiveReplayLeaderboardContextType.liveClimb.fieldPopulation == .climbers)
        #expect(LiveReplayLeaderboardContextType.routineTemplate.fieldPopulation == .climbers)
        #expect(LiveReplayLeaderboardContextType.justClimb.fieldPopulation == .completions)
        #expect(LiveReplayLeaderboardContextType.routine.fieldPopulation == .completions)
    }

    @Test
    func fieldSizeLabelNamesThePopulationAndGroupsTheNumber() {
        #expect(LiveReplayFieldPopulation.climbers.fieldSizeLabel(count: 1_284) == "1,284 CLIMBERS")
        #expect(LiveReplayFieldPopulation.completions.fieldSizeLabel(count: 60) == "60 COMPLETIONS")
    }

    /// A board with one finisher is the most-read board there is - it is the one the
    /// First Ascent holder returns to.
    @Test
    func fieldSizeLabelStaysSingularForAFieldOfOne() {
        #expect(LiveReplayFieldPopulation.climbers.fieldSizeLabel(count: 1) == "1 CLIMBER")
        #expect(LiveReplayFieldPopulation.completions.fieldSizeLabel(count: 1) == "1 COMPLETION")
    }
}
