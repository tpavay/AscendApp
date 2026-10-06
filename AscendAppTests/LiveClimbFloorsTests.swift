import Foundation
import SwiftData
import Testing

@testable import AscendApp

/// Floors climbed, as every live surface states them while a climb is running.
///
/// The number on screen has to be the one the saved workout carries - `Workout.floors` is what
/// the weekly recap and the leaderboard totals sum - so these pin the conversion at each floor
/// boundary, and then that a running session, a finished one and one restored after the app was
/// killed all read it the same way.
@MainActor
struct LiveClimbFloorsTests {
    // MARK: - The definition

    @Test(
        "A floor turns over at half a floor of steps",
        arguments: [
            (0, 0), (1, 0), (7, 0), (8, 1), (15, 1), (16, 1), (23, 1), (24, 2), (31, 2), (32, 2),
            (39, 2), (40, 3), (1_000, 63), (1_576, 99), (20_000, 1_250),
        ]
    )
    func floorsTurnOverAtTheHalfFloor(steps: Int, floors: Int) {
        #expect(FloorsClimbed.count(forSteps: steps) == floors)
    }

    @Test("The live count is the saved workout's count for every step total a climb can reach")
    func theLiveCountIsTheSavedWorkoutsCount() {
        #expect(FloorsClimbed.stepsPerFloor == 16, "saved workouts and the server's weekly totals were written at sixteen steps a floor")
        #expect(Workout.defaultStepsPerFloor == FloorsClimbed.stepsPerFloor)

        for steps in 0...50_000 {
            let saved = Int((Double(steps) / 16).rounded())
            guard FloorsClimbed.count(forSteps: steps) == saved, Workout.stepsToFloors(steps) == saved else {
                Issue.record("\(steps) steps: live \(FloorsClimbed.count(forSteps: steps)), workout \(Workout.stepsToFloors(steps)), saved rule \(saved)")
                return
            }
        }
    }

    @Test("A conversion rate that cannot divide states no floors rather than trapping")
    func aRateThatCannotDivideStatesNoFloors() {
        #expect(FloorsClimbed.count(forSteps: 1_000, stepsPerFloor: 0) == 0)
        #expect(FloorsClimbed.count(forSteps: 1_000, stepsPerFloor: -16) == 0)
    }

    @Test("The phrase counts one floor in the singular and groups thousands")
    func thePhraseAgreesWithItsCount() {
        #expect(FloorsClimbed.phrase(0) == "0 floors")
        #expect(FloorsClimbed.phrase(1) == "1 floor")
        #expect(FloorsClimbed.phrase(2) == "2 floors")
        #expect(FloorsClimbed.phrase(1_250) == "\(1_250.formatted()) floors")
        #expect(FloorsClimbed.phrase(forSteps: 8) == "1 floor")
    }

    // MARK: - The Live Activity

    @Test("The Lock Screen states the floors of the steps beside them and stores nothing new")
    func theLockScreenDerivesFloorsFromItsSteps() throws {
        let state = LiveClimbActivityAttributes.ContentState(
            steps: 1_000,
            rank: 4,
            rankTotal: 27,
            ownClimbs: nil,
            board: .racing,
            durationSeconds: 600,
            progress: 0.63,
            status: .recording,
            climbPhotoURLString: nil,
            updatedAt: Date(timeIntervalSince1970: 1_787_957_195)
        )
        #expect(state.floors == 63)
        #expect(state.floorsLabel == "63 floors")

        let stored = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any]
        )
        #expect(stored["floors"] == nil, "floors are derived, so an older binary's state and this one's stay one shape: \(stored.keys.sorted())")
    }

    @Test("A Live Activity an older binary started states its floors once this one draws it")
    func aStateFromAnOlderBinaryStatesItsFloors() throws {
        let stored = #"{"steps":497,"rankTotal":0,"durationSeconds":350,"progress":0.3,"status":"recording","updatedAt":0}"#
        let state = try JSONDecoder().decode(
            LiveClimbActivityAttributes.ContentState.self,
            from: Data(stored.utf8)
        )
        #expect(state.floors == 31)
        #expect(state.floorsLabel == "31 floors")
    }

    // MARK: - A running session

    @Test("A session's floors follow its step count across each boundary")
    func aSessionsFloorsFollowItsSteps() throws {
        let container = try Self.makeContainer()
        let (viewModel, motionSession) = Self.session(goal: JustClimbGoal(kind: .open))
        viewModel.start(modelContext: container.mainContext)

        for (steps, floors) in [(0, 0), (7, 0), (8, 1), (23, 1), (24, 2), (999, 62), (1_000, 63)] {
            motionSession.stepCount = steps
            #expect(viewModel.displayedFloors == floors, "\(steps) steps")
            #expect(viewModel.displayedFloors == Workout.stepsToFloors(viewModel.totalRecordedSteps))
        }
    }

    @Test("Floors hold while the clock runs on with no new steps")
    func floorsHoldWhileTheClockRunsWithoutSteps() throws {
        let container = try Self.makeContainer()
        let (viewModel, motionSession) = Self.session(goal: JustClimbGoal(kind: .open))
        viewModel.start(modelContext: container.mainContext)
        motionSession.stepCount = 1_000
        motionSession.duration = 600

        let standingStill = viewModel.displayedFloors
        motionSession.duration = 900
        #expect(viewModel.displayedFloors == standingStill)
        #expect(standingStill == 63)
    }

    @Test("Floors stop at the summit with the step count, however far the sensor runs on")
    func floorsStopAtTheSummitWithTheStepCount() throws {
        let container = try Self.makeContainer()
        let (viewModel, motionSession) = Self.session(goal: JustClimbGoal(kind: .steps, stepCount: 1_576))
        viewModel.start(modelContext: container.mainContext)

        motionSession.stepCount = 1_700
        #expect(viewModel.totalRecordedSteps == 1_576)
        #expect(viewModel.displayedFloors == 99, "1,576 steps is 98.5 floors, which the saved workout rounds to 99")
    }

    // MARK: - The saved workout

    @Test(
        "The last floors a session shows are the floors its saved workout carries",
        arguments: [8, 1_000, 1_576, 4_321]
    )
    func theLastFloorsShownAreTheSavedWorkoutsFloors(steps: Int) async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let (viewModel, motionSession) = Self.session(goal: JustClimbGoal(kind: .open))
        let startedAt = Date().addingTimeInterval(-600)
        motionSession.stopResult = HeadphoneMotionSessionResult(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            duration: 600,
            steps: steps,
            sampleCount: 3,
            stopReason: .userStopped
        )

        viewModel.start(modelContext: context)
        motionSession.stepCount = steps
        motionSession.duration = 600
        let shown = viewModel.displayedFloors

        await viewModel.finishAndSave(modelContext: context, reason: .userStopped)

        let workout = try #require(try context.fetch(FetchDescriptor<Workout>()).first)
        #expect(workout.steps == steps)
        #expect(workout.floors == shown)
        #expect(workout.stepsPerFloor == FloorsClimbed.stepsPerFloor)
    }

    // MARK: - A climb restored after the app was killed

    @Test("A restored climb states the floors of the steps it checkpointed, and saves the same")
    func aRestoredClimbStatesTheFloorsItCheckpointed() throws {
        let container = try Self.makeContainer()
        let draft = ActiveHeadphoneWorkoutDraft(
            sessionID: "floors-restore-\(UUID().uuidString)",
            kind: .justClimb,
            startedAt: Date(timeIntervalSinceNow: -600),
            title: "Just Climb",
            subtitle: "",
            workoutName: "Just Climb",
            targetStepCount: nil,
            targetDurationSeconds: nil
        )
        draft.applyCheckpoint(
            steps: 1_000,
            durationSeconds: 600,
            sampleCount: 30_000,
            splitCurve: nil,
            trackingIntegrity: .verified,
            stepCorrections: []
        )

        // One way out of a killed session: saved straight from the recovery prompt.
        let recovered = ActiveHeadphoneWorkoutDraftSaver.makeRecoveredWorkout(from: draft, deviceModel: "iPhone")
        #expect(recovered.steps == 1_000)
        #expect(recovered.floors == 63, "1,000 steps is 62.5 floors")

        // The other: resumed, and climbed on from.
        let (viewModel, motionSession) = Self.session(goal: JustClimbGoal(kind: .open), recoveredDraft: draft)
        viewModel.start(modelContext: container.mainContext)

        // The sensor resumes its count from the checkpoint it is handed
        // (`HeadphoneMotionSessionService.startRecording`); the fake only records it.
        let resumed = try #require(motionSession.lastResumeState, "a restored session resumes from its draft")
        #expect(resumed.steps == 1_000)
        motionSession.stepCount = resumed.steps
        motionSession.duration = resumed.duration

        #expect(viewModel.displayedFloors == recovered.floors, "resumed or saved, the restored climb states one figure")

        motionSession.stepCount = 1_016
        #expect(viewModel.displayedFloors == 64)
    }

    // MARK: - Fixtures

    private static func session(
        goal: JustClimbGoal,
        recoveredDraft: ActiveHeadphoneWorkoutDraft? = nil
    ) -> (LiveClimbSessionViewModel, FakeHeadphoneMotionSession) {
        let motionSession = FakeHeadphoneMotionSession()
        let viewModel = LiveClimbSessionViewModel(
            justClimbGoal: goal,
            motionSession: motionSession,
            climbService: ClimbService(catalogRepository: StubClimbCatalogRepository(climbs: [])),
            leaderboardService: StubLiveReplayLeaderboardService(),
            heartRateMonitor: HeartRateMonitorService(
                userDefaults: UserDefaults(suiteName: "LiveClimbFloorsTests.\(UUID().uuidString)")!
            ),
            currentUserId: { "test-user-id" },
            recoveredDraft: recoveredDraft
        )
        return (viewModel, motionSession)
    }

    private static func makeContainer() throws -> ModelContainer {
        try RetainedModelContainer.inMemory(
            for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self,
            ClimbAttempt.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self
        )
    }
}
