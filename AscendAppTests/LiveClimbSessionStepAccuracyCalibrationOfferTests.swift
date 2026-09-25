import Foundation
import SwiftData
import Testing

@testable import AscendApp

/// End-to-end wiring evidence: the optional post-climb step-accuracy calibration prompt is
/// offered for a saved session regardless of whether the climb completed or was saved incomplete
/// (`ClimbAttemptStatus.failed`), and is suppressed below the minimum-step floor either way.
/// `StepAccuracyCalibrationOfferPolicyTests` covers the floor logic in isolation; this proves
/// `LiveClimbSessionViewModel` actually wires it in for both attempt statuses.
@MainActor
struct LiveClimbSessionStepAccuracyCalibrationOfferTests {
    @Test("A completed climb above the floor offers calibration")
    func offersForACompletedClimbAboveTheFloor() async throws {
        let viewModel = try await Self.recordAndSaveAClimb(
            climb: Self.climb,
            appSteps: 2_600,
            reason: .targetReached
        )

        #expect(viewModel.phase == .saved(.completed))
        #expect(viewModel.shouldOfferStepAccuracyCalibration)
    }

    @Test("An incomplete, saved-progress climb above the floor also offers calibration")
    func offersForAnIncompleteClimbAboveTheFloor() async throws {
        let viewModel = try await Self.recordAndSaveAClimb(
            climb: Self.climb,
            appSteps: 150,
            reason: .userStopped
        )

        #expect(viewModel.phase == .saved(.failed))
        #expect(viewModel.shouldOfferStepAccuracyCalibration)
    }

    @Test("An incomplete climb saved after only a handful of steps never offers calibration")
    func suppressesForATriviallyShortIncompleteClimb() async throws {
        let viewModel = try await Self.recordAndSaveAClimb(
            climb: Self.climb,
            appSteps: 7,
            reason: .userStopped
        )

        #expect(viewModel.phase == .saved(.failed))
        #expect(!viewModel.shouldOfferStepAccuracyCalibration)
    }

    @Test("A completed climb whose target sits under the floor never offers calibration")
    func suppressesForACompletedClimbUnderTheFloor() async throws {
        let viewModel = try await Self.recordAndSaveAClimb(
            climb: Self.tinyClimb,
            appSteps: 50,
            reason: .targetReached
        )

        #expect(viewModel.phase == .saved(.completed))
        #expect(!viewModel.shouldOfferStepAccuracyCalibration)
    }

    @Test("A Just Climb saved after a handful of steps toward a 2,000-step goal never offers calibration")
    func suppressesForATriviallyShortJustClimb() async throws {
        // The captain's reported case: a 2,000-step Just Climb goal, saved after 7 steps. Just
        // Climb has no attempt to fail, so this resolves `.saved(.completed)` regardless of how
        // little of the goal was reached - only the step-count floor decides here.
        let viewModel = try await Self.recordAndSaveAJustClimb(
            goal: JustClimbGoal(kind: .steps, stepCount: 2_000),
            appSteps: 7,
            reason: .userStopped
        )

        #expect(viewModel.phase == .saved(.completed))
        #expect(!viewModel.shouldOfferStepAccuracyCalibration)
    }

    @Test("A Just Climb saved above the floor toward a 2,000-step goal offers calibration")
    func offersForAJustClimbAboveTheFloor() async throws {
        let viewModel = try await Self.recordAndSaveAJustClimb(
            goal: JustClimbGoal(kind: .steps, stepCount: 2_000),
            appSteps: 150,
            reason: .userStopped
        )

        #expect(viewModel.phase == .saved(.completed))
        #expect(viewModel.shouldOfferStepAccuracyCalibration)
    }

    // MARK: - Setup

    private static func recordAndSaveAJustClimb(
        goal: JustClimbGoal,
        appSteps: Int,
        reason: HeadphoneMotionSessionStopReason
    ) async throws -> LiveClimbSessionViewModel {
        let startedAt = Date().addingTimeInterval(-600)
        let motionSession = FakeHeadphoneMotionSession()
        motionSession.stopResult = HeadphoneMotionSessionResult(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            duration: 600,
            steps: appSteps,
            sampleCount: 3,
            stopReason: reason
        )

        let container = try RetainedModelContainer.inMemory(
            for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self,
            ClimbAttempt.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self
        )
        let context = container.mainContext

        let viewModel = LiveClimbSessionViewModel(
            justClimbGoal: goal,
            motionSession: motionSession,
            leaderboardService: StubLiveReplayLeaderboardService(),
            currentUserId: { "test-user-id" }
        )

        viewModel.start(modelContext: context)
        await viewModel.finishAndSave(modelContext: context, reason: reason)

        return viewModel
    }

    private static func recordAndSaveAClimb(
        climb: Climb,
        appSteps: Int,
        reason: HeadphoneMotionSessionStopReason
    ) async throws -> LiveClimbSessionViewModel {
        let startedAt = Date().addingTimeInterval(-600)
        let motionSession = FakeHeadphoneMotionSession()
        motionSession.stopResult = HeadphoneMotionSessionResult(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            duration: 600,
            steps: appSteps,
            sampleCount: 3,
            stopReason: reason
        )

        let container = try RetainedModelContainer.inMemory(
            for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self,
            ClimbAttempt.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self
        )
        let context = container.mainContext

        let viewModel = LiveClimbSessionViewModel(
            climb: climb,
            motionSession: motionSession,
            climbService: ClimbService(catalogRepository: StubClimbCatalogRepository(climbs: [climb])),
            leaderboardService: StubLiveReplayLeaderboardService(),
            currentUserId: { "test-user-id" }
        )

        viewModel.start(modelContext: context)
        await viewModel.finishAndSave(modelContext: context, reason: reason)

        return viewModel
    }

    private static let climb = Climb(
        id: "calibration-offer-test-tower",
        name: "Test Tower",
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

    private static let tinyClimb = Climb(
        id: "calibration-offer-test-tiny-tower",
        name: "Tiny Tower",
        city: "Toronto",
        country: "Canada",
        continent: "North America",
        latitude: 43.6426,
        longitude: -79.3871,
        totalHeightMeters: 10,
        totalHeightFeet: 33,
        realClimbableHeightMeters: nil,
        realClimbableHeightFeet: nil,
        totalSteps: 50,
        realStairCount: 50,
        calculatedFloors: 3,
        category: "tower",
        tier: .common,
        tags: [],
        funFact: "Fact",
        sourceURL: "https://example.com",
        imageSetVersion: 1,
        releaseState: .available
    )
}
