@preconcurrency import CoreMotion
import Foundation
import SwiftData
import Testing

@testable import AscendApp

/// A climber's first session used to meet Motion & Fitness at GO: iOS raises that alert the first
/// time an app starts headphone motion updates, which Ascend only did once the countdown finished.
/// A climber who had already turned to the machine or locked the phone counted nothing until they
/// came back and answered it, and an authorization error during that window ended the attempt for
/// good. Every later session had the answer already, so only the first one ever failed.
///
/// These pin the order that fixes it - Motion & Fitness answered before the countdown, the workout
/// session (and Apple's one-time "Health and Fitness Data" notice) started with the countdown, and
/// a refused stream held rather than failed - without headphones, which the simulator lacks.
@MainActor
@Suite("First-session Motion & Fitness")
struct FirstSessionMotionAccessTests {
    // MARK: - Before the countdown

    @Test("A first session asks for Motion & Fitness and waits for the answer before its countdown")
    func firstSessionAsksBeforeCountdown() async {
        let manager = FakeHeadphoneMotionManager()
        let authorization = FakeMotionAuthorization(.notDetermined)
        var polls = 0
        var updatesStartedBeforeAnswer = false
        let gate = HeadphoneMotionAccessGate(
            makeManager: { manager },
            authorization: { authorization.state },
            sleep: { _ in
                polls += 1
                updatesStartedBeforeAnswer = manager.isDeviceMotionActive
                // The climber reads the alert for well past the unprompted grace, then allows it.
                if polls == 40 {
                    authorization.state = .authorized
                }
            }
        )
        // The alert takes the app out of `.active` for as long as it is on screen.
        gate.isAppActive = false

        let access = await gate.resolve()

        #expect(access == .authorized)
        #expect(polls == 40, "the countdown waited for the answer instead of timing out")
        #expect(updatesStartedBeforeAnswer, "starting updates is what raises the alert")
        #expect(manager.startDeviceMotionCallCount == 1)
        #expect(!manager.isDeviceMotionActive, "the alert-raising stream stops once answered")
        #expect(
            HeadphoneSessionStartRequirement(motionAccess: access, headphones: .ready) == .ready
        )
    }

    @Test("Refusing Motion & Fitness blocks the countdown and sends the climber to Settings")
    func refusalBlocksCountdown() async {
        let manager = FakeHeadphoneMotionManager()
        let authorization = FakeMotionAuthorization(.notDetermined)
        let gate = HeadphoneMotionAccessGate(
            makeManager: { manager },
            authorization: { authorization.state },
            sleep: { _ in authorization.state = .denied }
        )

        let access = await gate.resolve()

        #expect(access == .denied)
        #expect(!manager.isDeviceMotionActive)
        #expect(
            HeadphoneSessionStartRequirement(motionAccess: access, headphones: .ready) == .motionAccessBlocked
        )
    }

    @Test(
        "A later session never meets the alert",
        arguments: [HeadphoneMotionAuthorizationState.authorized, .denied, .restricted]
    )
    func answeredAccessNeverPrompts(state: HeadphoneMotionAuthorizationState) async {
        var madeManager = false
        let gate = HeadphoneMotionAccessGate(
            makeManager: {
                madeManager = true
                return FakeHeadphoneMotionManager()
            },
            authorization: { state },
            sleep: { _ in Issue.record("an answered climber must not wait") }
        )

        #expect(await gate.resolve() == state)
        #expect(!madeManager)
    }

    @Test("When iOS shows no alert, the countdown goes ahead after the grace instead of hanging")
    func noAlertFallsThrough() async {
        var polls = 0
        let gate = HeadphoneMotionAccessGate(
            makeManager: { FakeHeadphoneMotionManager() },
            authorization: { .notDetermined },
            sleep: { _ in polls += 1 }
        )
        gate.isAppActive = true

        let access = await gate.resolve()

        #expect(access == .notDetermined)
        #expect(polls == Int(HeadphoneMotionAccessGate.unpromptedGrace / HeadphoneMotionAccessGate.pollInterval))
        #expect(
            HeadphoneSessionStartRequirement(motionAccess: access, headphones: .ready) == .ready
        )
    }

    @Test("Leaving the screen while the alert is up stops waiting")
    func cancellationStopsWaiting() async {
        let manager = FakeHeadphoneMotionManager()
        let gate = HeadphoneMotionAccessGate(
            makeManager: { manager },
            authorization: { .notDetermined },
            sleep: { _ in throw CancellationError() }
        )

        #expect(await gate.resolve() == .notDetermined)
        #expect(!manager.isDeviceMotionActive)
    }

    @Test(
        "Motion & Fitness outranks headphones, and a flow that skips the headphone check only needs access",
        arguments: [
            (HeadphoneMotionAuthorizationState.denied, HeadphoneMotionReadiness?.some(.ready), HeadphoneSessionStartRequirement.motionAccessBlocked),
            (.restricted, .some(.unavailable), .motionAccessBlocked),
            (.authorized, .some(.unavailable), .headphonesRequired),
            (.notDetermined, .some(.unavailable), .headphonesRequired),
            (.authorized, .some(.ready), .ready),
            (.authorized, nil, .ready),
            (.denied, nil, .motionAccessBlocked)
        ]
    )
    func startRequirement(
        access: HeadphoneMotionAuthorizationState,
        headphones: HeadphoneMotionReadiness?,
        expected: HeadphoneSessionStartRequirement
    ) {
        #expect(HeadphoneSessionStartRequirement(motionAccess: access, headphones: headphones) == expected)
    }

    // MARK: - The workout session starts with the countdown

    @Test("The countdown starts the workout session, and GO does not start a second one")
    func countdownStartsWorkoutSession() throws {
        let background = FakeLiveClimbBackgroundSession()
        let motionSession = FakeHeadphoneMotionSession()
        let viewModel = LiveClimbSessionViewModel(
            justClimbGoal: JustClimbGoal(),
            motionSession: motionSession,
            backgroundSessionService: background,
            draftStore: ActiveHeadphoneWorkoutDraftStore(userDefaults: Self.isolatedDefaults())
        )

        viewModel.prepareBackgroundSessionForCountdown()

        #expect(background.startCallCount == 1, "Apple's one-time notice lands during the countdown")
        #expect(motionSession.startRecordingCallCount == 0)

        let container = try Self.container()
        viewModel.start(modelContext: container.mainContext)

        #expect(motionSession.startRecordingCallCount == 1)
        #expect(background.startCallCount == 1)
        #expect(background.isRunning)

        viewModel.cancelPreparedBackgroundSession()
        #expect(background.stopCallCount == 0, "a recording climb keeps its workout session")
    }

    @Test("A countdown that never reaches GO stops the workout session it started")
    func abandonedCountdownStopsWorkoutSession() {
        let background = FakeLiveClimbBackgroundSession()
        let viewModel = LiveClimbSessionViewModel(
            justClimbGoal: JustClimbGoal(),
            motionSession: FakeHeadphoneMotionSession(),
            backgroundSessionService: background
        )

        viewModel.prepareBackgroundSessionForCountdown()
        viewModel.cancelPreparedBackgroundSession()
        viewModel.cancelPreparedBackgroundSession()

        #expect(background.startCallCount == 1)
        #expect(background.stopCallCount == 1)
        #expect(!background.isRunning)
    }

    @Test("GO that fails to start recording stops the workout session the countdown started")
    func failedStartStopsWorkoutSession() throws {
        let background = FakeLiveClimbBackgroundSession()
        let motionSession = FakeHeadphoneMotionSession()
        motionSession.startError = HeadphoneMotionSessionError.motionUnavailable
        let viewModel = LiveClimbSessionViewModel(
            justClimbGoal: JustClimbGoal(),
            motionSession: motionSession,
            backgroundSessionService: background,
            draftStore: ActiveHeadphoneWorkoutDraftStore(userDefaults: Self.isolatedDefaults())
        )

        viewModel.prepareBackgroundSessionForCountdown()
        viewModel.start(modelContext: try Self.container().mainContext)

        #expect(viewModel.phase == .failed(HeadphoneMotionSessionError.motionUnavailable.localizedDescription))
        #expect(background.stopCallCount == 1)
        #expect(!background.isRunning)
    }

    @Test("A routine's countdown starts the workout session before any motion is read")
    func routineCountdownStartsWorkoutSession() throws {
        let manager = FakeHeadphoneMotionManager()
        let background = FakeLiveClimbBackgroundSession()
        let viewModel = ActiveRoutineViewModel(
            routine: Self.routine(),
            motionSession: HeadphoneMotionSessionService(
                motionManager: manager,
                motionAccess: { .authorized }
            ),
            backgroundSessionService: background,
            draftStore: ActiveHeadphoneWorkoutDraftStore(userDefaults: Self.isolatedDefaults())
        )
        let container = try Self.container()

        viewModel.startSession(modelContext: container.mainContext)
        defer { viewModel.stopTimer() }

        #expect(viewModel.phase == .countdown)
        #expect(background.startCallCount == 1)
        #expect(manager.startDeviceMotionCallCount == 0)

        viewModel.cancelPreparedBackgroundSession()
        #expect(background.stopCallCount == 1)
    }

    // MARK: - A refused stream is held, not failed

    @Test(
        "An authorization error is only as final as the answer behind it",
        arguments: [
            (CMErrorMotionActivityNotAuthorized.rawValue, HeadphoneMotionAuthorizationState.notDetermined, HeadphoneMotionErrorDisposition.restart),
            (CMErrorNotAuthorized.rawValue, .authorized, .restart),
            (CMErrorMotionActivityNotAuthorized.rawValue, .denied, .awaitMotionAccess),
            (CMErrorNotAuthorized.rawValue, .restricted, .awaitMotionAccess),
            (CMErrorNotEntitled.rawValue, .authorized, .fatal),
            (CMErrorMotionActivityNotAvailable.rawValue, .authorized, .fatal),
            (CMErrorDeviceRequiresMovement.rawValue, .authorized, .restart)
        ]
    )
    func errorDisposition(
        errorCode: UInt32,
        access: HeadphoneMotionAuthorizationState,
        expected: HeadphoneMotionErrorDisposition
    ) {
        let nsError = NSError(domain: CMErrorDomain, code: Int(errorCode))
        #expect(HeadphoneMotionErrorDisposition(error: nsError, motionAccess: access) == expected)
    }

    @Test("Motion & Fitness turned off mid-climb holds the climb and resumes it when turned back on")
    func refusalMidClimbResumes() async throws {
        let manager = FakeHeadphoneMotionManager()
        let authorization = FakeMotionAuthorization(.authorized)
        let session = HeadphoneMotionSessionService(
            motionManager: manager,
            motionAccess: { authorization.state }
        )
        try session.startRecording()
        #expect(manager.startDeviceMotionCallCount == 1)

        authorization.state = .denied
        manager.deliver(error: CMErrorMotionActivityNotAuthorized)
        try await Self.waitUntil { session.isMotionAccessDenied }

        #expect(session.status == .waitingForMotion, "held, never failed")
        #expect(session.status.isRecording)

        session.handleRecordingTick(at: Date())
        #expect(manager.startDeviceMotionCallCount == 1, "a refused stream is not restarted into the same refusal")

        authorization.state = .authorized
        session.handleRecordingTick(at: Date())

        #expect(!session.isMotionAccessDenied)
        try await Self.waitUntil { manager.startDeviceMotionCallCount == 2 }
        _ = try await session.stopRecording()
    }

    @Test("An authorization error while the alert is still unanswered keeps retrying")
    func unansweredAlertKeepsRetrying() async throws {
        let manager = FakeHeadphoneMotionManager()
        let session = HeadphoneMotionSessionService(
            motionManager: manager,
            motionAccess: { .notDetermined }
        )
        try session.startRecording()

        manager.deliver(error: CMErrorMotionActivityNotAuthorized)
        try await Self.waitUntil { manager.startDeviceMotionCallCount == 2 }

        #expect(session.status.isRecording)
        #expect(!session.isMotionAccessDenied)
        _ = try await session.stopRecording()
    }

    @Test("A device that can never deliver headphone motion still fails the session")
    func unavailableMotionStillFails() async throws {
        let manager = FakeHeadphoneMotionManager()
        let session = HeadphoneMotionSessionService(
            motionManager: manager,
            motionAccess: { .authorized }
        )
        try session.startRecording()

        manager.deliver(error: CMErrorNotEntitled)
        try await Self.waitUntil {
            if case .failed = session.status { return true }
            return false
        }
        #expect(!session.isMotionAccessDenied)
    }

    // MARK: - Helpers

    private static func waitUntil(
        timeout: Duration = .seconds(3),
        _ condition: @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            guard clock.now < deadline else {
                Issue.record("condition not met within \(timeout)")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private static func isolatedDefaults() -> UserDefaults {
        let suiteName = "FirstSessionMotionAccessTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private static func container() throws -> ModelContainer {
        try RetainedModelContainer.inMemory(
            for: ActiveHeadphoneWorkoutDraft.self, Workout.self, WorkoutSourceLink.self,
            WorkoutParticipation.self, ClimbAttempt.self, BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self
        )
    }

    private static func routine() -> Routine {
        Routine(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            name: "First Session Routine",
            source: .builtin,
            intervals: [
                RoutineInterval(duration: 60, intensityValue: 8, order: 0)
            ],
            templateId: "first_session_routine"
        )
    }
}
