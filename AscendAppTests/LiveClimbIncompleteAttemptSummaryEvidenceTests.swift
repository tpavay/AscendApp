import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// Reproduces a real climber's reported flow end to end through the shipping
/// `LiveClimbSessionView`: partial progress on a landmark climb, tap "End attempt", confirm the
/// save, and read what lands on screen afterward.
///
/// Two things were in question. First, whether the same confirmation overlay that a zero-step
/// "End attempt" tap shows also covers a non-zero, incomplete attempt - it does, through the one
/// `endAttemptOverlay`, parameterized on `totalRecordedSteps`. Second, whether saving that
/// incomplete attempt then shows the same rich completion summary (splits, pace trend) a full
/// completion gets - it did not: `shouldShowRankedCompletionSummary` gated the summary on
/// `.saved(.completed)` only, so an incomplete save fell through to a two-line "steps saved"
/// notice with no splits at all. This suite pins the fix: any saved attempt reaches the summary,
/// an incomplete one just carries no rank.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct LiveClimbIncompleteAttemptSummaryEvidenceTests {
    @Test("Ending an incomplete attempt shows the same confirmation overlay as ending a zero-step one, then a full summary with no rank")
    func incompleteAttemptConfirmsAndSummarizes() async throws {
        let container = try RetainedModelContainer.inMemory(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            ClimbAttempt.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self
        )
        let context = container.mainContext

        // Empire State Building's real target is 1,576 steps (`Climb.preview`). The reported
        // climber reached 1,560 - sixteen short, a genuine DNF rather than a target-reached
        // completion that merely looked incomplete.
        let climb = Climb.preview
        let startedAt = Date().addingTimeInterval(-3_600)
        let motionSession = FakeHeadphoneMotionSession()
        motionSession.stepCount = 1_560
        motionSession.stopResult = HeadphoneMotionSessionResult(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(3_600),
            duration: 3_600,
            steps: 1_560,
            sampleCount: 1_800,
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

        try await RenderedScreen.host(
            LiveClimbSessionView(viewModel: viewModel)
                .environment(ModerationStore.shared)
                .modelContainer(container)
        ) { screen in
            try activateAccessibilityElement(labelled: "End attempt", in: screen.window)

            // Question 1: the same overlay a zero-step end shows, parameterized for a real,
            // non-zero, incomplete step count - not a second, silently-skippable path.
            let confirmationCopy = try await screen.copy { $0.contains("save this progress") }
            try screen.photograph(named: "live-climb-incomplete-01-end-attempt-confirmation")
            #expect(
                confirmationCopy.contains("1,560 steps recorded"),
                "The confirmation overlay has to name the real, non-zero step count"
            )
            #expect(
                confirmationCopy.contains("save this progress or discard the attempt"),
                "A non-zero incomplete attempt gets the save-or-discard overlay, not silence"
            )
            #expect(
                confirmationCopy.contains("no steps have been recorded") == false,
                "The zero-step copy must not leak onto a real, non-zero attempt"
            )

            try activateAccessibilityElement(labelled: "Save progress", in: screen.window)

            // Question 2: saving an incomplete attempt has to reach the same completion summary
            // component a full completion gets - splits included - not the old two-line notice.
            let summaryCopy = try await screen.copy { $0.contains("splits") }
            try screen.photograph(named: "live-climb-incomplete-02-completion-summary")

            #expect(summaryCopy.contains("splits"), "An incomplete save still earns its splits")
            #expect(summaryCopy.contains("1,560"), "The summary's stats grid has to show the real total")
            #expect(
                summaryCopy.contains("steps saved") == false,
                "The old bare notice must be gone now that the real summary renders"
            )

            let elements = try await screen.elements()
            let rankLabels = elements.compactMap(\.accessibilityLabel).filter {
                $0.localizedCaseInsensitiveContains("of 1") || $0.localizedCaseInsensitiveContains("climbers")
            }
            #expect(
                rankLabels.isEmpty,
                "A DNF never publishes to the replay index, so the summary must assert no rank: \(rankLabels)"
            )
        }
    }
}
