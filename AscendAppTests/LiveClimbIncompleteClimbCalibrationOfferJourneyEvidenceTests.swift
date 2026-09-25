import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// Product-level evidence that the optional post-climb step-accuracy calibration prompt is
/// offered on an INCOMPLETE, saved-progress climb's summary - not only on a completed one.
///
/// A climb is recorded and saved-early through the real `LiveClimbSessionViewModel` (steps below
/// the climb's target, so it settles `.saved(.failed)` - "saved progress", never a completion),
/// the shipping `LiveClimbSessionView` is hosted in a live window through `RenderedScreen`, and
/// `DONE` is pressed through the same accessibility action a climber's tap produces. Both moments
/// are photographed when `ASCEND_EVIDENCE_DIR` is set.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct LiveClimbIncompleteClimbCalibrationOfferJourneyEvidenceTests {
    @Test("The calibration prompt is offered on an incomplete, saved-progress climb's summary")
    func calibrationPromptFollowsAnIncompleteClimbsSummary() async throws {
        let container = try RetainedModelContainer.inMemory(
            for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self,
            ClimbAttempt.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self
        )
        let context = container.mainContext

        let viewModel = try await recordAndSaveAnIncompleteClimb(in: context)
        #expect(
            viewModel.phase == .saved(.failed),
            "Saving early below the target has to settle as saved progress, not a completion"
        )
        #expect(
            viewModel.shouldOfferStepAccuracyCalibration,
            "An incomplete climb above the step floor still has something to calibrate"
        )

        try await RenderedScreen.host(
            LiveClimbSessionView(viewModel: viewModel)
                .environment(ModerationStore.shared)
                .modelContainer(container)
        ) { screen in
            let summaryText = try await screen.copy { $0.contains("done") }
            try screen.photograph(named: "live-climb-incomplete-calibration-01-progress-saved-summary")

            // The empty Best Effort cache makes this session trivially "the most steps ever",
            // which takes the achievement card's title ahead of "PROGRESS SAVED" - a documented,
            // unrelated precedence rule (`LiveClimbCompletionSummaryView.achievementTitle`). What
            // this test is proving is unranked: no leaderboard placement is drawn for a climb
            // that never reached its target.
            #expect(summaryText.contains("done"))
            #expect(summaryText.contains("150"))
            #expect(
                !viewModel.shouldShowRankedCompletionSummary,
                "An incomplete climb never earns a leaderboard placement"
            )

            _ = try await screen.elements()
            try activateAccessibilityElement(labelled: "DONE", in: screen.window)

            let calibrationText = try await screen.copy { $0.contains("sharpen the count") }
            try screen.photograph(named: "live-climb-incomplete-calibration-02-prompt-after-done")

            #expect(
                calibrationText.contains("sharpen the count"),
                "Dismissing an incomplete climb's summary with DONE has to reach the calibration sheet"
            )
            #expect(calibrationText.contains("150 steps"))

            try activateAccessibilityElement(labelled: "Skip", in: screen.window)

            for _ in 0..<60 where screen.window.rootViewController?.presentedViewController != nil {
                try await screen.settle(.turns(1))
                try await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    // MARK: - The climb

    private func recordAndSaveAnIncompleteClimb(
        in context: ModelContext
    ) async throws -> LiveClimbSessionViewModel {
        let climb = Self.climb
        let startedAt = Date().addingTimeInterval(-90)
        let motionSession = FakeHeadphoneMotionSession()
        motionSession.stopResult = HeadphoneMotionSessionResult(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(90),
            duration: 90,
            steps: 150,
            sampleCount: 3,
            stopReason: .userStopped
        )

        let viewModel = LiveClimbSessionViewModel(
            climb: climb,
            motionSession: motionSession,
            climbService: ClimbService(
                catalogRepository: StubClimbCatalogRepository(climbs: [climb])
            ),
            leaderboardService: StubLiveReplayLeaderboardService()
        )

        viewModel.start(modelContext: context)
        await viewModel.finishAndSave(modelContext: context, reason: .userStopped)

        return viewModel
    }

    private static let climb = Climb(
        id: "incomplete-calibration-test-tower",
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
