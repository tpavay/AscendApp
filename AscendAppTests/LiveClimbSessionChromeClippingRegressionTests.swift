import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// Regression coverage for the reported left-edge clipping of `topChrome` and `LiveClimbJustMeView`
/// during an active recording on the Just Me tab with the climb's photo background showing.
/// `LiveClimbJustMeRedesignEvidenceTests` (added in PR #582) only ever asserts copy *presence*
/// (`text.contains(...)`) - a string glued flush against the screen's left edge, with no leading
/// margin at all, still "contains" every substring the old test checked, so that suite could not
/// have caught a leading-inset regression here. This suite asserts *position*: each anchor's
/// on-screen frame must start at or past the row's own leading inset, both immediately after the
/// screen mounts (settle: .turns(1), sampling before the recording-start transition has settled)
/// and again once it has fully settled - confirmed to fail loudly (`frame.minX == 0`) against a
/// deliberately reintroduced missing-padding regression on `topChrome`.
///
/// This does not, on its own, reproduce the transient single-frame compositor artifact the captain's
/// screenshot may have caught: SwiftUI's reported accessibility frame reflects the current declared
/// layout, not an in-flight CALayer presentation value, so a purely transient animation-timing glitch
/// is invisible to this (or any `RenderedScreen`-based) assertion - confirmed empirically: this test
/// passes identically whether `topChrome`'s conditional-removal code (pre-fix) or its stable-identity
/// collapse (post-fix) is in place. The fix in `LiveClimbSessionView.topChrome` and
/// `liveLeaderboardSection` (stable view identity instead of `if`-insert/remove, plus a single
/// coordinated 0.25s animation shared with `sessionBackground`'s photo crossfade and
/// `LiveClimbSessionTabBar`'s tab-switch animation) is a structural fix for a real, verified
/// animation/identity-churn inconsistency independent of this test; this test's job is to lock down
/// the leading-margin invariant so no *settled* state - the vast majority of what any user sees -
/// ever regresses to `topChrome`/`LiveClimbJustMeView` text sitting at the screen's edge.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct LiveClimbSessionChromeClippingRegressionTests {
    private static let leadingInset: CGFloat = 20

    @Test("topChrome and Just Me content never clip at the leading edge mid-transition")
    func chromeStaysUnclippedThroughoutRecordingStartTransition() async throws {
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

        // Started before hosting, mirroring the real countdown->recording handoff: the view mounts
        // with `viewModel.phase == .recording` already true while its own `hasStartedRecording`
        // state still defaults to false until `.onAppear` catches up - exactly the transition window
        // that produced the reported defect.
        viewModel.start(modelContext: context)
        motionSession.stepCount = 6
        motionSession.duration = 5

        try await RenderedScreen.host(
            LiveClimbSessionView(viewModel: viewModel)
                .environment(ModerationStore.shared)
                .modelContainer(container),
            settle: .turns(1)
        ) { screen in
            try await Self.assertNothingClipsAtLeadingEdge(on: screen, phase: "immediately after mount")

            try await screen.settle(.turns(12))
            try await Self.assertNothingClipsAtLeadingEdge(on: screen, phase: "after full settle")
        }
    }

    private static func assertNothingClipsAtLeadingEdge(
        on screen: HostedScreen,
        phase: String
    ) async throws {
        let anchors = ["Berlin TV Tower", "Berlin, Germany", "ELAPSED", "REMAINING", "CURRENT RANK"]

        for anchor in anchors {
            let frame = try await screen.frame(ofElementLabelled: anchor)
            let unwrapped = try #require(frame, "\(anchor) never appeared on screen (\(phase))")
            #expect(
                unwrapped.minX >= leadingInset - 2,
                "\(anchor) clipped at the leading edge (\(phase)): frame.minX = \(unwrapped.minX)"
            )
        }
    }

    private static let climb = Climb(
        id: "chrome-clipping-regression-test-tower",
        name: "Berlin TV Tower",
        city: "Berlin",
        country: "Germany",
        continent: "Europe",
        latitude: 52.0,
        longitude: 13.0,
        totalHeightMeters: 300,
        totalHeightFeet: 984,
        realClimbableHeightMeters: nil,
        realClimbableHeightFeet: nil,
        totalSteps: 986,
        realStairCount: 986,
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
