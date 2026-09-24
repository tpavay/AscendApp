import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// Product-level evidence that the Just Me tab's hero and stat grid (#599's redesign) render
/// correctly for every `JustClimbGoalKind`, not just the step goal the redesign shipped with.
/// Captain-reported 2026-09-24: an open Just Climb's hero showed the climb-type "OPEN CLIMB"
/// tag where the "steps" unit label belonged, and a duration goal had no hero fraction and no
/// summit bar at all - `LiveClimbJustMeView` only ever asked `mode.targetStepCount`. Read off
/// the real, shipping `LiveClimbSessionView` mid-recording, not a redrawn copy.
///
/// Photographed when `ASCEND_EVIDENCE_DIR` is set, and not drawn otherwise.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct LiveClimbJustMeGoalTypeEvidenceTests {
    @Test("An open Just Climb's hero shows only the step count and a STEPS label - no goal fraction, no OPEN CLIMB tag, no summit bar")
    func openJustClimbShowsStepsOnly() async throws {
        let container = try Self.makeContainer()
        let motionSession = FakeHeadphoneMotionSession()
        let viewModel = LiveClimbSessionViewModel(
            justClimbGoal: JustClimbGoal(kind: .open),
            motionSession: motionSession,
            climbService: ClimbService(catalogRepository: StubClimbCatalogRepository(climbs: [])),
            leaderboardService: StubLiveReplayLeaderboardService()
        )

        viewModel.start(modelContext: container.mainContext)
        motionSession.stepCount = 7
        motionSession.duration = 40

        #expect(viewModel.mode.targetStepCount == nil)
        #expect(viewModel.mode.targetDuration == nil)

        try await RenderedScreen.host(
            LiveClimbSessionView(viewModel: viewModel)
                .environment(ModerationStore.shared)
                .modelContainer(container)
        ) { screen in
            let text = try await screen.copy()

            #expect(text.contains("7"))
            #expect(text.contains("steps"))
            #expect(!text.contains("open climb"), "the climb-type tag must not stand in for the unit label on an open Just Climb: \(text)")
            #expect(!text.contains(" of "), "an open Just Climb has no target to measure a fraction against: \(text)")
            #expect(!text.contains("%"), "an open Just Climb has no summit bar and no percentage: \(text)")

            try screen.photograph(named: "just-me-goal-type-open")
        }
    }

    @Test("A step-goal Just Climb keeps the current-of-goal hero and the summit bar unchanged")
    func stepGoalJustClimbShowsCurrentOfGoal() async throws {
        let container = try Self.makeContainer()
        let motionSession = FakeHeadphoneMotionSession()
        let viewModel = LiveClimbSessionViewModel(
            justClimbGoal: JustClimbGoal(kind: .steps, stepCount: 900),
            motionSession: motionSession,
            climbService: ClimbService(catalogRepository: StubClimbCatalogRepository(climbs: [])),
            leaderboardService: StubLiveReplayLeaderboardService()
        )

        viewModel.start(modelContext: container.mainContext)
        motionSession.stepCount = 300
        motionSession.duration = 754 // 12:34

        #expect(viewModel.mode.targetStepCount == 900)

        try await RenderedScreen.host(
            LiveClimbSessionView(viewModel: viewModel)
                .environment(ModerationStore.shared)
                .modelContainer(container)
        ) { screen in
            let text = try await screen.copy()

            #expect(text.contains("300"))
            #expect(text.contains("of"))
            #expect(text.contains("900 steps"))
            #expect(text.contains("33%"), "300/900 steps = 33% on the summit bar")
            #expect(text.contains("elapsed"), "the top-left box stays ELAPSED on a step goal")

            try screen.photograph(named: "just-me-goal-type-steps")
        }
    }

    @Test("A duration-goal Just Climb's hero shows elapsed-of-goal time with the summit bar, and moves steps into the top-left box")
    func durationGoalJustClimbShowsElapsedOfGoal() async throws {
        let container = try Self.makeContainer()
        let motionSession = FakeHeadphoneMotionSession()
        let viewModel = LiveClimbSessionViewModel(
            justClimbGoal: JustClimbGoal(kind: .duration, durationMinutes: 20),
            motionSession: motionSession,
            climbService: ClimbService(catalogRepository: StubClimbCatalogRepository(climbs: [])),
            leaderboardService: StubLiveReplayLeaderboardService()
        )

        viewModel.start(modelContext: container.mainContext)
        motionSession.stepCount = 412
        motionSession.duration = 750 // 12:30

        #expect(viewModel.mode.targetStepCount == nil)
        #expect(viewModel.mode.targetDuration == 1200) // 20 minutes

        try await RenderedScreen.host(
            LiveClimbSessionView(viewModel: viewModel)
                .environment(ModerationStore.shared)
                .modelContainer(container)
        ) { screen in
            let text = try await screen.copy()

            #expect(text.contains("12:30"), "the hero's elapsed time: \(text)")
            #expect(text.contains("of"))
            #expect(text.contains("20:00"), "the hero's goal duration: \(text)")
            #expect(text.contains("63%"), "12:30 elapsed of a 20:00 goal = 62.5%, rounds to 63% on the summit bar")
            #expect(text.contains("412"), "steps move into the top-left box when time is the hero: \(text)")
            #expect(!text.contains("open climb"))
            #expect(!text.contains("elapsed"), "the top-left box is relabeled STEPS on a duration goal, so the word ELAPSED must not appear: \(text)")

            try screen.photograph(named: "just-me-goal-type-duration")
        }
    }

    @Test(
        "Neither the open nor the duration-goal hero spills past the screen's side gutter, at iPhone SE and standard widths",
        arguments: LiveClimbJustMePhotoBackgroundWidthTests.phoneSizes
    )
    func openAndDurationHeroesStayInsideTheScreen(size: CGSize) async throws {
        try await Self.assertNoOverflow(
            goal: JustClimbGoal(kind: .open),
            steps: 7,
            duration: 40,
            expectedLabels: ["Just Me", "Leaderboard", "STEPS", "ELAPSED", "CURRENT RANK", "AVERAGE", "End attempt"],
            size: size
        )
        try await Self.assertNoOverflow(
            goal: JustClimbGoal(kind: .duration, durationMinutes: 20),
            steps: 412,
            duration: 750,
            expectedLabels: ["Just Me", "Leaderboard", "of", "20:00", "STEPS", "CURRENT RANK", "AVERAGE", "End attempt"],
            size: size
        )
    }

    private static func assertNoOverflow(
        goal: JustClimbGoal,
        steps: Int,
        duration: TimeInterval,
        expectedLabels: [String],
        size: CGSize
    ) async throws {
        let container = try Self.makeContainer()
        let motionSession = FakeHeadphoneMotionSession()
        let viewModel = LiveClimbSessionViewModel(
            justClimbGoal: goal,
            motionSession: motionSession,
            climbService: ClimbService(catalogRepository: StubClimbCatalogRepository(climbs: [])),
            leaderboardService: StubLiveReplayLeaderboardService()
        )

        viewModel.start(modelContext: container.mainContext)
        motionSession.stepCount = steps
        motionSession.duration = duration

        try await RenderedScreen.host(
            LiveClimbSessionView(viewModel: viewModel)
                .environment(ModerationStore.shared)
                .modelContainer(container),
            size: size
        ) { screen in
            let inside = screen.bounds.insetBy(dx: 8, dy: 0)
            for label in expectedLabels {
                guard let frame = try await screen.frame(ofElementLabelled: label, reading: 40) else {
                    Issue.record("\(label) is not painted on the Just Me tab (goal: \(goal.kind)) at \(Int(size.width))pt")
                    continue
                }
                #expect(
                    inside.contains(frame),
                    "\(label) at \(frame.integral) spills past the screen's side gutter \(inside.integral) (goal: \(goal.kind)) at \(Int(size.width))pt"
                )
            }
        }
    }

    private static func makeContainer() throws -> ModelContainer {
        try RetainedModelContainer.inMemory(
            for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self,
            ClimbAttempt.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self
        )
    }
}
