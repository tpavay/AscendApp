import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// Product-level evidence for the captain's reported case: a Just Climb toward a 2,000-step goal
/// saved after 7 steps. The shipping `LiveClimbSessionView` is hosted in a live window, `DONE` is
/// pressed through the same accessibility action a climber's tap produces, and the test reads
/// whether the calibration sheet follows - it must not for a trivially short save, and must for
/// one above the step floor.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct LiveClimbJustClimbCalibrationOfferJourneyEvidenceTests {
    @Test("DONE on a 7-step Just Climb toward a 2,000-step goal never raises the calibration sheet")
    func trivialJustClimbSkipsCalibration() async throws {
        let (container, viewModel) = try await recordAndSaveAJustClimb(appSteps: 7)
        #expect(!viewModel.shouldOfferStepAccuracyCalibration)

        try await RenderedScreen.host(
            LiveClimbSessionView(viewModel: viewModel)
                .environment(ModerationStore.shared)
                .modelContainer(container)
        ) { screen in
            _ = try await screen.copy { $0.contains("done") }
            try screen.photograph(named: "live-climb-just-climb-7-steps-01-summary")

            _ = try await screen.elements()
            try activateAccessibilityElement(labelled: "DONE", in: screen.window)

            for _ in 0..<40 {
                try await screen.settle(.turns(1))
                try await Task.sleep(for: .milliseconds(20))
            }
            let afterDone = try await screen.copy()
            try screen.photograph(named: "live-climb-just-climb-7-steps-02-after-done")

            #expect(
                screen.window.rootViewController?.presentedViewController == nil,
                "A 7-step save is below the floor, so DONE must not present the calibration sheet"
            )
            #expect(!afterDone.contains("sharpen the count"))
        }
    }

    @Test("DONE on a 150-step Just Climb toward a 2,000-step goal raises the calibration sheet")
    func justClimbAboveFloorOffersCalibration() async throws {
        let (container, viewModel) = try await recordAndSaveAJustClimb(appSteps: 150)
        #expect(viewModel.shouldOfferStepAccuracyCalibration)

        try await RenderedScreen.host(
            LiveClimbSessionView(viewModel: viewModel)
                .environment(ModerationStore.shared)
                .modelContainer(container)
        ) { screen in
            _ = try await screen.copy { $0.contains("done") }
            try screen.photograph(named: "live-climb-just-climb-150-steps-01-summary")

            _ = try await screen.elements()
            try activateAccessibilityElement(labelled: "DONE", in: screen.window)

            let calibrationText = try await screen.copy { $0.contains("sharpen the count") }
            try screen.photograph(named: "live-climb-just-climb-150-steps-02-prompt-after-done")

            #expect(calibrationText.contains("sharpen the count"))
            #expect(calibrationText.contains("150 steps"))

            try activateAccessibilityElement(labelled: "Skip", in: screen.window)

            for _ in 0..<60 where screen.window.rootViewController?.presentedViewController != nil {
                try await screen.settle(.turns(1))
                try await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    private func recordAndSaveAJustClimb(
        appSteps: Int
    ) async throws -> (ModelContainer, LiveClimbSessionViewModel) {
        let container = try RetainedModelContainer.inMemory(
            for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self,
            ClimbAttempt.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self
        )
        let context = container.mainContext

        let startedAt = Date().addingTimeInterval(-90)
        let motionSession = FakeHeadphoneMotionSession()
        motionSession.stopResult = HeadphoneMotionSessionResult(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(90),
            duration: 90,
            steps: appSteps,
            sampleCount: 3,
            stopReason: .userStopped
        )

        let viewModel = LiveClimbSessionViewModel(
            justClimbGoal: JustClimbGoal(kind: .steps, stepCount: 2_000),
            motionSession: motionSession,
            leaderboardService: StubLiveReplayLeaderboardService(),
            currentUserId: { "test-user-id" }
        )

        viewModel.start(modelContext: context)
        await viewModel.finishAndSave(modelContext: context, reason: .userStopped)

        return (container, viewModel)
    }
}
