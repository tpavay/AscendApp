import Foundation
import SwiftData
import Testing

@testable import AscendApp

/// The session view model's two pace readings, as the PACE card consumes them.
@MainActor
struct LiveClimbSessionPaceTests {
    @Test("A fresh session states no pace until the clock has run")
    func freshSessionStatesNoPace() throws {
        let (viewModel, motionSession) = try Self.startedSession()

        #expect(viewModel.currentStepsPerMinute == nil)
        #expect(viewModel.averageStepsPerMinute == nil)
        #expect(viewModel.currentPaceDisplay == "—")
        #expect(viewModel.averagePaceDisplay == "—")

        motionSession.stepCount = 3
        motionSession.duration = 2
        #expect(viewModel.currentStepsPerMinute == nil, "two seconds and three steps is not a pace")
    }

    @Test("Average is total steps over elapsed minutes, and current agrees until the window has run")
    func averageAndCurrentAgreeInsideTheFirstWindow() throws {
        let (viewModel, motionSession) = try Self.startedSession()

        motionSession.stepCount = 300
        motionSession.duration = 754

        #expect(viewModel.averageStepsPerMinute == 24)
        #expect(viewModel.currentStepsPerMinute == 24)
        #expect(viewModel.currentPaceDisplay == "24")
        #expect(viewModel.averagePaceDisplay == "24")
    }

    @Test("Current pace follows the last thirty seconds the ticks recorded")
    func currentFollowsTheTicks() throws {
        let (viewModel, motionSession) = try Self.startedSession()

        for second in 1...60 {
            motionSession.duration = TimeInterval(second)
            motionSession.stepCount = second
            viewModel.recordLiveSplitSample()
        }
        for second in 61...90 {
            motionSession.duration = TimeInterval(second)
            motionSession.stepCount = 60 + (second - 60) * 2
            viewModel.recordLiveSplitSample()
        }

        #expect(viewModel.currentStepsPerMinute == 120)
        #expect(viewModel.averageStepsPerMinute == 80)
    }

    @Test("A landmark climb's pace counts the clamped step total, never steps past the summit")
    func paceCountsTheClampedTotal() throws {
        let (viewModel, motionSession) = try Self.startedSession()

        motionSession.stepCount = 1_500
        motionSession.duration = 600

        #expect(viewModel.totalRecordedSteps == 900)
        #expect(viewModel.averageStepsPerMinute == 90)
    }

    private static func startedSession() throws -> (LiveClimbSessionViewModel, FakeHeadphoneMotionSession) {
        let container = try RetainedModelContainer.inMemory(
            for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self,
            ClimbAttempt.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self
        )
        let motionSession = FakeHeadphoneMotionSession()
        let viewModel = LiveClimbSessionViewModel(
            climb: climb,
            motionSession: motionSession,
            climbService: ClimbService(catalogRepository: StubClimbCatalogRepository(climbs: [climb])),
            leaderboardService: StubLiveReplayLeaderboardService()
        )
        viewModel.start(modelContext: container.mainContext)
        motionSession.status = .recording
        return (viewModel, motionSession)
    }

    private static let climb = Climb(
        id: "session-pace-test-tower",
        name: "Pace Tower",
        city: "Testville",
        country: "Testland",
        continent: "North America",
        latitude: 40.0,
        longitude: -74.0,
        totalHeightMeters: 300,
        totalHeightFeet: 984,
        realClimbableHeightMeters: nil,
        realClimbableHeightFeet: nil,
        totalSteps: 900,
        realStairCount: 900,
        calculatedFloors: 45,
        category: "tower",
        tier: .gold,
        tags: [],
        funFact: "Fact",
        sourceURL: "https://example.com",
        imageSetVersion: 1,
        releaseState: .available
    )
}
