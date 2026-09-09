import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// Product-level evidence for the Just Me tab redesign: a plain-language step
/// count header, a horizontal summit bar carrying the live percentage, and a
/// three-card stat row (Elapsed/Remaining/Rank) - all read off the real,
/// shipping `LiveClimbSessionView` mid-recording, not a redrawn copy.
///
/// Photographed when `ASCEND_EVIDENCE_DIR` is set, and not drawn otherwise.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct LiveClimbJustMeRedesignEvidenceTests {
    @Test("The Just Me tab states steps plainly and drops the old percentage-tiny rail")
    func justMeStatesStepsPlainlyDuringARealClimb() async throws {
        let container = try RetainedModelContainer.inMemory(
            for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self,
            ClimbAttempt.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self
        )
        let context = container.mainContext

        let climb = Self.climb
        let motionSession = FakeHeadphoneMotionSession()

        let viewModel = LiveClimbSessionViewModel(
            climb: climb,
            motionSession: motionSession,
            climbService: ClimbService(
                catalogRepository: StubClimbCatalogRepository(climbs: [climb])
            ),
            leaderboardService: StubLiveReplayLeaderboardService()
        )

        viewModel.start(modelContext: context)
        motionSession.stepCount = 300
        motionSession.duration = 754 // 12:34

        #expect(viewModel.isRecording, "The redesigned chrome (photo background, ring badge) only shows while recording")
        #expect(viewModel.mode.targetStepCount == 900)

        try await RenderedScreen.host(
            LiveClimbSessionView(viewModel: viewModel)
                .environment(ModerationStore.shared)
                .modelContainer(container)
        ) { screen in
            let text = try await screen.copy()

            // Plain-language "X of Y steps" header, not a percentage-first number.
            #expect(text.contains("300"))
            #expect(text.contains("of"))
            #expect(text.contains("900 steps"))

            // The redundant raw-steps card is gone; REMAINING replaces it.
            #expect(text.contains("remaining"))
            #expect(text.contains("600"), "900 target - 300 recorded = 600 steps remaining")
            #expect(text.contains("elapsed"))
            #expect(text.contains("current rank"))
            #expect(!text.contains("pace"), "the PACE · SPM card was dropped from this tab's redesign")

            // The live percentage rides the summit bar's fill, mid-climb (300/900 = 33%).
            #expect(text.contains("33%"))

            try screen.photograph(named: "just-me-redesign-mid-climb")
        }
    }

    private static let climb = Climb(
        id: "just-me-redesign-test-tower",
        name: "Test Tower",
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
