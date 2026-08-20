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

/// A field size is never carried without the noun that characterises it, because a bare
/// total is exactly what made two correct boards read as a contradiction.
struct LiveReplayFieldSizeTests {
    @Test
    func labelNamesThePopulationItCounts() {
        #expect(
            LiveReplayFieldSize(population: .climbers, count: 27).label == "27 CLIMBERS"
        )
        #expect(
            LiveReplayFieldSize(population: .completions, count: 60).label == "60 COMPLETIONS"
        )
    }
}

/// The panel may only state a field it can substantiate. Its rows cannot: a live session
/// synthesizes a lone current-user row before the first fetch and whenever one fails, so a
/// board that had reached nobody still claimed a field of one.
@MainActor
struct LiveClimbSessionFieldSizeTests {
    @Test
    func aLandmarkBoardStatesNoFieldBeforeTheServerCountArrives() {
        let viewModel = LiveClimbSessionViewModel(
            climb: Self.climb,
            motionSession: FakeHeadphoneMotionSession(),
            climbService: ClimbService(
                catalogRepository: StubFieldSizeClimbCatalogRepository(climbs: [Self.climb])
            ),
            leaderboardService: StubFieldSizeLeaderboardService()
        )

        #expect(viewModel.leaderboardRows.count == 1)
        #expect(viewModel.leaderboardField == nil)
    }

    /// An open Just Climb races every completed attempt, and the only total on hand counts
    /// distinct finishers. Naming that "completions" would be false, so it names nothing.
    @Test
    func anOpenJustClimbBoardStatesNoField() {
        let viewModel = LiveClimbSessionViewModel(
            justClimbGoal: JustClimbGoal(),
            motionSession: FakeHeadphoneMotionSession(),
            climbService: ClimbService(
                catalogRepository: StubFieldSizeClimbCatalogRepository(climbs: [])
            ),
            leaderboardService: StubFieldSizeLeaderboardService()
        )

        #expect(viewModel.replayContext.type.fieldPopulation == .completions)
        #expect(viewModel.leaderboardField == nil)
    }

    private static let climb = Climb(
        id: "field-size-test-tower",
        name: "CN Tower",
        city: "Toronto",
        country: "Canada",
        continent: "North America",
        latitude: 43.6426,
        longitude: -79.3871,
        totalHeightMeters: 553,
        totalHeightFeet: 1_815,
        realClimbableHeightMeters: nil,
        realClimbableHeightFeet: nil,
        totalSteps: 2_579,
        realStairCount: 2_579,
        calculatedFloors: 144,
        category: "tower",
        tier: .gold,
        tags: [],
        funFact: "Fact",
        sourceURL: "https://example.com",
        imageSetVersion: 1,
        releaseState: .available
    )
}

private struct StubFieldSizeClimbCatalogRepository: ClimbCatalogRepository {
    let climbs: [Climb]

    func loadInitialCatalog() throws -> ClimbCatalogSnapshot {
        ClimbCatalogSnapshot(
            climbs: climbs,
            source: .bootstrap,
            catalogVersion: 0,
            featuredClimbId: climbs.first?.id,
            updatedAt: nil
        )
    }

    func refreshCatalog() async throws -> ClimbCatalogSnapshot {
        try loadInitialCatalog()
    }
}

/// Keeps these off the network: the rule under test is what the panel states before any
/// board has answered.
private struct StubFieldSizeLeaderboardService: LiveReplayLeaderboardServicing {
    func fetchSummary(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayLeaderboardSummary {
        .empty
    }

    func fetchCompletionRank(
        context: LiveReplayLeaderboardContext,
        completionDurationSeconds: TimeInterval,
        finalSteps: Int
    ) async throws -> LiveReplayCompletionRank {
        throw CancellationError()
    }

    func fetchCompletionRankSnapshot(
        context: LiveReplayLeaderboardContext,
        workoutId: String
    ) async throws -> LiveReplayCompletionRankSnapshot? {
        nil
    }

    func fetchPublishStatus(workoutId: String) async throws -> LiveReplayPublishStatus? {
        nil
    }

    func fetchCurrentUserBestCompletion(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayCurrentUserCompletion? {
        nil
    }

    func fetchCurrentUserFinisherStatus(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayFinisherStatus? {
        nil
    }

    func fetchCompletionLeaderboard(
        context: LiveReplayLeaderboardContext,
        limit: Int,
        cursor: LiveReplayCompletionLeaderboardCursor?,
        forceRefresh: Bool
    ) async throws -> LiveReplayCompletionLeaderboard {
        throw CancellationError()
    }

    func refreshIfNeeded(
        context: LiveReplayLeaderboardContext,
        elapsedSeconds: Int,
        currentSteps: Int,
        force: Bool
    ) async throws -> LiveReplayLeaderboardWindow? {
        nil
    }
}
