import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// Evidence that Ascend Mountain presents the real Just Climb session - the shipping
/// `LiveClimbSessionView` mid-recording with its own view model - and that every build offers it.
///
/// Photographed when `ASCEND_EVIDENCE_DIR` is set, and not drawn otherwise.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct AscendMountainSessionEvidenceTests {
    @Test("Mountain reads the session's own steps, pace and time in place of the Just Me and Leaderboard tabs")
    func mountainShowsTheSessionsNumbersWithoutTheTabs() async throws {
        let container = try Self.makeContainer()
        let (viewModel, motionSession) = Self.recordingSession(goal: JustClimbGoal(kind: .open), container: container)
        motionSession.stepCount = 1_842
        motionSession.duration = 504 // 8:24

        try await RenderedScreen.host(
            LiveClimbSessionView(viewModel: viewModel, experience: .mountain)
                .environment(ModerationStore.shared)
                .modelContainer(container)
        ) { screen in
            let text = try await screen.copy()

            #expect(text.contains("1,842"), "the step count is the workout's: \(text)")
            #expect(text.contains("steps"))
            #expect(text.contains("spm"))
            #expect(text.contains("8:24"), "elapsed is the workout's clock: \(text)")
            #expect(text.contains("end attempt"), "ending stays the session's own control: \(text)")
            #expect(!text.contains("just me"), "the Classic tabs give way to the Mountain read-out: \(text)")
            #expect(!text.contains("leaderboard"))
            #expect(!text.contains("to go"), "an open climb has no goal line: \(text)")
            #expect(!text.contains("bpm"), "no heart-rate field without a strap: \(text)")
#if !DEBUG
            #expect(!text.contains("fps"), "the developer overlay never ships: \(text)")
#endif

            try screen.photograph(named: "ascend-mountain-session-open")
        }
    }

    @Test("A step goal on Mountain states what is left to climb")
    func mountainStepGoalShowsStepsToGo() async throws {
        let container = try Self.makeContainer()
        let (viewModel, motionSession) = Self.recordingSession(
            goal: JustClimbGoal(kind: .steps, stepCount: 2_000),
            container: container
        )
        motionSession.stepCount = 1_250
        motionSession.duration = 600

        try await RenderedScreen.host(
            LiveClimbSessionView(viewModel: viewModel, experience: .mountain)
                .environment(ModerationStore.shared)
                .modelContainer(container)
        ) { screen in
            let text = try await screen.copy()

            #expect(text.contains("1,250"))
            #expect(text.contains("750 to go"), "2,000 - 1,250: \(text)")

            try screen.photograph(named: "ascend-mountain-session-step-goal")
        }
    }

    @Test("Classic is untouched: the same session without Mountain keeps its tabs")
    func classicKeepsItsTabs() async throws {
        let container = try Self.makeContainer()
        let (viewModel, motionSession) = Self.recordingSession(goal: JustClimbGoal(kind: .open), container: container)
        motionSession.stepCount = 40
        motionSession.duration = 30

        try await RenderedScreen.host(
            LiveClimbSessionView(viewModel: viewModel)
                .environment(ModerationStore.shared)
                .modelContainer(container)
        ) { screen in
            let text = try await screen.copy()

            #expect(text.contains("just me"))
            #expect(text.contains("leaderboard"))
            #expect(text.contains("current rank"))
        }
    }

    @Test(
        "The Mountain read-out stays inside the screen at iPhone SE and standard widths",
        arguments: LiveClimbJustMePhotoBackgroundWidthTests.phoneSizes
    )
    func mountainReadOutStaysInsideTheScreen(size: CGSize) async throws {
        let container = try Self.makeContainer()
        let (viewModel, motionSession) = Self.recordingSession(
            goal: JustClimbGoal(kind: .steps, stepCount: 20_000),
            container: container
        )
        motionSession.stepCount = 18_888
        motionSession.duration = 7_199

        try await RenderedScreen.host(
            LiveClimbSessionView(viewModel: viewModel, experience: .mountain)
                .environment(ModerationStore.shared)
                .modelContainer(container),
            size: size
        ) { screen in
            let inside = screen.bounds.insetBy(dx: 8, dy: 0)
            for label in ["18,888", "STEPS", "1,112 TO GO", "SPM", "ELAPSED", "End attempt"] {
                guard let frame = try await screen.frame(ofElementLabelled: label, reading: 40) else {
                    Issue.record("\(label) is not painted on the Mountain read-out at \(Int(size.width))pt")
                    continue
                }
                #expect(
                    inside.contains(frame),
                    "\(label) at \(frame.integral) spills past the side gutter \(inside.integral) at \(Int(size.width))pt"
                )
            }
        }
    }

    @Test(
        "The counts beyond the pack sit under the step count and above the stats, inside the screen",
        arguments: LiveClimbJustMePhotoBackgroundWidthTests.phoneSizes
    )
    func countsBeyondThePackStayInsideTheScreen(size: CGSize) async throws {
        let container = try Self.makeContainer()
        let (viewModel, motionSession) = Self.recordingSession(goal: JustClimbGoal(kind: .open), container: container)
        motionSession.stepCount = 1_842
        motionSession.duration = 504
        let standing = LiveClimbStandingText(rank: 200, rankTotal: 896, standing: .racing(field: nil, ownClimbs: nil))
        let crowd = try #require(MountainCrowdCounts(standing: standing, drawn: .init(ahead: 6, behind: 4)))

        try await RenderedScreen.host(
            AscendMountainSessionHUD(viewModel: viewModel, debugState: nil, crowd: crowd)
                .padding(.horizontal, 16)
                .background(Color.black),
            size: size
        ) { screen in
            let inside = screen.bounds.insetBy(dx: 8, dy: 0)
            let steps = try #require(try await screen.frame(ofElementLabelled: "1,842", reading: 40))
            let ahead = try #require(try await screen.frame(ofElementLabelled: "193 more climbers ahead", reading: 40))
            let behind = try #require(try await screen.frame(ofElementLabelled: "692 more climbers behind", reading: 40))
            let pace = try #require(try await screen.frame(ofElementLabelled: "SPM", reading: 40))

            for frame in [ahead, behind] {
                #expect(inside.contains(frame), "\(frame.integral) spills past \(inside.integral) at \(Int(size.width))pt")
            }
            #expect(ahead.minY > steps.maxY, "ahead sits under the step count")
            #expect(behind.maxY < pace.minY, "behind sits above the stats")
            #expect(abs(ahead.midX - screen.bounds.midX) < 2, "centred")

            try screen.photograph(named: "ascend-mountain-crowd-counts-\(Int(size.width))")
        }
    }

    @Test("A climber who never chose opens Just Climb on the Mountain; a chosen Classic stays Classic")
    func setupSheetStartsOnTheMountainUntilAClimberChooses() async throws {
        let fresh = try #require(UserDefaults(suiteName: "just-climb-setup-\(UUID().uuidString)"))
        try await RenderedScreen.host(JustClimbSetupSheet { _, _ in }.defaultAppStorage(fresh)) { screen in
            let text = try await screen.copy()
            #expect(text.contains("your athlete"), "the Mountain's athlete chip shows only with Mountain picked: \(text)")
        }

        let chose = try #require(UserDefaults(suiteName: "just-climb-setup-\(UUID().uuidString)"))
        chose.set(JustClimbExperience.classic.rawValue, forKey: JustClimbSetupSheet.experienceKey)
        try await RenderedScreen.host(JustClimbSetupSheet { _, _ in }.defaultAppStorage(chose)) { screen in
            let text = try await screen.copy()
            #expect(!text.contains("your athlete"), "\(text)")
        }
    }

    @Test("Every build's setup sheet offers the Mountain beside Classic")
    func setupSheetOffersTheMountainInEveryBuild() async throws {
        try await RenderedScreen.host(JustClimbSetupSheet { _, _ in }) { screen in
            let text = try await screen.copy()

            #expect(text.contains("just climb"))
            #expect(text.contains("mountain"), "\(text)")
            #expect(text.contains("classic"), "\(text)")
        }
    }

    private static func recordingSession(
        goal: JustClimbGoal,
        container: ModelContainer
    ) -> (LiveClimbSessionViewModel, FakeHeadphoneMotionSession) {
        let motionSession = FakeHeadphoneMotionSession()
        let viewModel = LiveClimbSessionViewModel(
            justClimbGoal: goal,
            motionSession: motionSession,
            climbService: ClimbService(catalogRepository: StubClimbCatalogRepository(climbs: [])),
            leaderboardService: StubLiveReplayLeaderboardService()
        )
        viewModel.start(modelContext: container.mainContext)
        return (viewModel, motionSession)
    }

    private static func makeContainer() throws -> ModelContainer {
        try RetainedModelContainer.inMemory(
            for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self,
            ClimbAttempt.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self
        )
    }
}
