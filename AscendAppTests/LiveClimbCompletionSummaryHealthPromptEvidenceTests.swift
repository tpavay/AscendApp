import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// Product-level evidence that the completion summary stays focused on the earned result.
///
/// This hosts the shipping completion summary in a real phone-sized window with Health in the
/// never-connected state and a climb carrying no heart rate - the exact conditions the connect
/// offer used to appear under - and reads the screen's copy off the accessibility tree
/// (`RenderedScreen`), so the proof is that the view says nothing about heart rate rather than
/// relying on test setup to hide it. The photograph is written only under `ASCEND_EVIDENCE_DIR`.
@MainActor
@Suite(.hostsAWindow)
struct LiveClimbCompletionSummaryHealthPromptEvidenceTests {
    @Test("A completed climb summary never asks for Apple Health")
    func hidesHeartRateAbsenceAndKeepsSummaryActions() async throws {
        let previousAuthorizationState = HealthKitSyncState.hasRequestedAuthorization
        HealthKitSyncState.hasRequestedAuthorization = false
        defer { HealthKitSyncState.hasRequestedAuthorization = previousAuthorizationState }

        let container = try RetainedModelContainer.inMemory(for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self, ClimbAttempt.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self)
        let context = ModelContext(container)
        let workout = Workout(
            name: "CN Tower Live Climb",
            date: Date().addingTimeInterval(-1_908),
            duration: 1_908,
            steps: 2_579,
            floors: 144,
            source: .headphoneMotion
        )
        context.insert(workout)
        try context.save()

        #expect(workout.isInAppSensorWorkout, "the fixture has to be a climb enrichment tracks")
        #expect(workout.avgHeartRate == nil)
        #expect(workout.heartRateTimeSeries.isEmpty)

        let screen = LiveClimbCompletionSummaryView(
            climb: nil,
            workout: workout,
            leaderboardRank: 1,
            leaderboardTotal: 1,
            leaderboardRankBasis: .atCompletion,
            leaderboardContext: .justClimbGlobal(targetSteps: 2_579),
            moment: .freshCompletion,
            onDone: { _ in }
        )
        .modelContainer(container)

        try await RenderedScreen.host(screen, size: Self.screenSize) { hosted in
            let recognized = try await hosted.copy { $0.contains("done") }

            #expect(recognized.contains("no heart rate on this climb") == false)
            #expect(recognized.contains("connect apple health") == false)
            #expect(recognized.contains("heart rate") == false)
            #expect(recognized.contains("share"))
            #expect(recognized.contains("done"))

            try hosted.photograph(named: "live-climb-completion-summary-without-heart-rate-prompt")
        }
    }

    private static let screenSize = CGSize(width: 393, height: 852)
}
