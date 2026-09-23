import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// Product-level evidence for the Just Me tab redesign: a plain-language step
/// count header, a horizontal summit bar carrying the live percentage, and a
/// 2x2 stat grid (Elapsed/Elevation Climbed/Rank/Pace) - all read off the real,
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

            // The redundant raw-steps card is gone; ELEVATION CLIMBED replaces it -
            // 300/900 = 33% of the tower's 45 published floors is 15.
            #expect(text.contains("elevation climbed"))
            #expect(text.contains("15"), "300/900 steps is 33% of 45 floors = 15 floors climbed")
            #expect(text.contains("elapsed"))
            #expect(text.contains("current rank"))
            // The fourth card: current pace and the climb-so-far average sit side by side,
            // each carrying its own label, both in steps per minute (300 steps over 12:34 is
            // 24, and with no window of ticks yet the current reading is the same ratio).
            #expect(text.contains("pace (steps per minute)"), "the PACE card is back on this tab: \(text)")
            #expect(text.contains("current"))
            #expect(text.contains("average"))
            #expect(text.contains("24"), "300 steps / 12.57 minutes = 24 steps per minute")

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
