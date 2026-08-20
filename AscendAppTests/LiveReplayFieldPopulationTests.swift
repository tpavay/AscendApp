import Foundation
import SwiftData
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
@Suite(.serialized)
struct LiveClimbSessionFieldSizeTests {
    @Test
    func aLandmarkBoardStatesNoFieldBeforeTheServerCountArrives() {
        let viewModel = makeLandmarkSession(
            leaderboardService: StubLiveReplayLeaderboardService()
        )

        #expect(viewModel.leaderboardRows.count == 1)
        #expect(viewModel.leaderboardField == nil)
    }

    /// The screen the captain approved: the server's own finisher count, under the noun
    /// that says which population it counts.
    @Test
    func aLandmarkBoardStatesTheServerFinisherCount() async throws {
        let viewModel = makeLandmarkSession(
            leaderboardService: StubLiveReplayLeaderboardService(summary: Self.summary(totalClimbers: 27))
        )
        let container = try Self.makeContainer()
        let context = container.mainContext

        viewModel.start(modelContext: context)
        await viewModel.refreshReplayLeaderboardIfNeeded(force: true)

        let field = viewModel.leaderboardField
        #expect(field?.count == 27)
        #expect(field?.population == .climbers)
        #expect(field?.label == "27 CLIMBERS")

        await viewModel.discard(modelContext: context)
    }

    /// A blip on the session's one forced fetch used to silence the line for the whole
    /// race. The count is unknown until the server answers, then it is stated - and the
    /// asking is paced by the clock, not by how often the session ticks.
    @Test
    func aFailedOpeningFetchRecoversOnALaterTick() async throws {
        let leaderboardService = StubLiveReplayLeaderboardService(
            summary: Self.summary(totalClimbers: 27),
            summaryFetchFailureCount: 1
        )
        let viewModel = makeLandmarkSession(leaderboardService: leaderboardService)
        let container = try Self.makeContainer()
        let context = container.mainContext
        let startedAt = Date(timeIntervalSince1970: 1_777_777_700)

        viewModel.start(modelContext: context)
        await viewModel.refreshReplayLeaderboardIfNeeded(force: true, now: startedAt)

        #expect(viewModel.leaderboardField == nil)

        await viewModel.refreshReplayLeaderboardIfNeeded(now: startedAt.addingTimeInterval(1))

        #expect(
            leaderboardService.summaryFetchCount == 1,
            "A tick a second after the refusal is inside the retry interval"
        )
        #expect(viewModel.leaderboardField == nil)

        await viewModel.refreshReplayLeaderboardIfNeeded(now: startedAt.addingTimeInterval(6))

        #expect(viewModel.leaderboardField?.count == 27)

        await viewModel.refreshReplayLeaderboardIfNeeded(now: startedAt.addingTimeInterval(20))

        #expect(
            leaderboardService.summaryFetchCount == 2,
            "Once the server has answered, the summary is never read again"
        )

        await viewModel.discard(modelContext: context)
    }

    /// The rows are what a climber is racing; the count beneath them is garnish. A
    /// summary the server refuses must cost the line and nothing else.
    @Test
    func aRefusedSummaryLeavesTheRaceRowsStanding() async throws {
        let leaderboardService = StubLiveReplayLeaderboardService(
            summary: Self.summary(totalClimbers: 27),
            summaryFetchFailureCount: 99,
            window: Self.window
        )
        let viewModel = makeLandmarkSession(leaderboardService: leaderboardService)
        let container = try Self.makeContainer()
        let context = container.mainContext

        viewModel.start(modelContext: context)
        await viewModel.refreshReplayLeaderboardIfNeeded(force: true)

        #expect(viewModel.leaderboardField == nil)
        #expect(viewModel.leaderboardFetchFailed == false)
        #expect(viewModel.leaderboardRows.count > 1)

        await viewModel.discard(modelContext: context)
    }

    /// An open Just Climb races every completed attempt, and the only total on hand counts
    /// distinct finishers. Naming that "completions" would be false, so it names nothing.
    @Test
    func anOpenJustClimbBoardStatesNoField() async throws {
        let viewModel = LiveClimbSessionViewModel(
            justClimbGoal: JustClimbGoal(),
            motionSession: FakeHeadphoneMotionSession(),
            climbService: ClimbService(
                catalogRepository: StubClimbCatalogRepository(climbs: [])
            ),
            leaderboardService: StubLiveReplayLeaderboardService(
                summary: Self.summary(totalClimbers: 1_284)
            )
        )
        let container = try Self.makeContainer()
        let context = container.mainContext

        viewModel.start(modelContext: context)
        await viewModel.refreshReplayLeaderboardIfNeeded(force: true)

        #expect(viewModel.replayContext.type.fieldPopulation == .completions)
        #expect(viewModel.leaderboardField == nil)

        await viewModel.discard(modelContext: context)
    }

    private func makeLandmarkSession(
        leaderboardService: StubLiveReplayLeaderboardService
    ) -> LiveClimbSessionViewModel {
        LiveClimbSessionViewModel(
            climb: Self.climb,
            motionSession: FakeHeadphoneMotionSession(),
            climbService: ClimbService(
                catalogRepository: StubClimbCatalogRepository(climbs: [Self.climb])
            ),
            leaderboardService: leaderboardService
        )
    }

    private static let window = LiveReplayLeaderboardWindow(
        context: .liveClimb(climbId: climb.id, targetSteps: climb.referenceStepCount),
        bucketIndex: 0,
        currentSteps: 0,
        fetchedAt: Date(timeIntervalSince1970: 1_777_777_700),
        rows: [
            LiveReplayLeaderboardRow(
                id: "rival-1",
                rank: 1,
                displayName: "Rival",
                avatarToken: "rival",
                photoURL: nil,
                stepsAtBucket: 400,
                finalSteps: 2_579,
                deltaFromUser: 400,
                isCurrentUser: false,
                isPersonalBest: false,
                completionDurationSeconds: 900,
                userId: "rival-1"
            )
        ],
        currentUserRank: 2,
        totalClimbers: 27
    )

    private static func summary(totalClimbers: Int) -> LiveReplayLeaderboardSummary {
        LiveReplayLeaderboardSummary(
            totalClimbers: totalClimbers,
            completedCount: totalClimbers,
            personalBestDurationSeconds: nil,
            updatedAt: Date(timeIntervalSince1970: 1_777_777_700)
        )
    }

    private static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: AscendLocalStore.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
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
