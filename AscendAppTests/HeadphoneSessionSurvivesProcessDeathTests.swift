import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import AscendApp

/// The regression suite for the 2026-10-23 Empire State Building stall (uid ZVm34nnd...): the
/// process died about a minute into a Live Climb, the Lock Screen kept showing "66 steps, 1:02"
/// for twenty minutes, and the recovery screen's Resume Live restarted from the dead draft and
/// silently dropped the gap. Grown from the scout's headless reproduction so that every mode -
/// Live Climb, Just Climb and Routine - is held to the same contract
/// (`docs/headphone-session-recovery.md`):
///
/// 1. the draft survives the process at its last checkpoint;
/// 2. the next launch resumes by itself, with the gap credited and recorded as an interruption;
/// 3. every Live Activity update carries a stale date;
/// 4. a phone that was off lands on the recovery screen with the machine's count and Save first;
/// 5. a checkpoint the store refuses goes to the JSON fallback file with a diagnostic, and the
///    next launch reads it back.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct HeadphoneSessionSurvivesProcessDeathTests {
    /// 2026-10-23T11:20:54Z, the `live_climb_attempt_started` event in Mixpanel.
    private static let goAt = Date(timeIntervalSince1970: 1_792_754_454)
    /// 2026-10-23T11:41:21Z, the recovery screen's `screen_view` in Mixpanel.
    private static let recoveryShownAt = Date(timeIntervalSince1970: 1_792_755_681)

    enum Mode: String, CaseIterable, Sendable {
        case liveClimb
        case justClimb
        case routine

        var draftKind: ActiveHeadphoneWorkoutDraftKind {
            switch self {
            case .liveClimb: .liveClimb
            case .justClimb: .justClimb
            case .routine: .routine
            }
        }
    }

    // MARK: - 1. The draft survives the process

    @Test("A session killed after its 62-second checkpoint leaves a draft of 66 steps and 1:02", arguments: Mode.allCases)
    func killedProcessLeavesTheDraftAtTheLastCheckpoint(mode: Mode) async throws {
        let lab = try Lab(mode: mode)
        let session = try lab.startedSession()
        lab.run(session, seconds: 62)

        let draft = try #require(try lab.draftStore.activeDraft(in: lab.context))
        #expect(draft.steps == 66)
        #expect(Int(draft.durationSeconds) == 62)
        #expect(draft.status == .recording)
        #expect(draft.kind == mode.draftKind)
        let curve = try #require(draft.splitCurve)
        #expect(curve.intervalSeconds == 10)
        #expect(curve.steps.last == 66, "the forced lifecycle checkpoint lands the 62s bucket at 66")

        // Every checkpoint writes what the process knew about its footing.
        let diagnostics = try #require(draft.checkpointDiagnostics)
        #expect(diagnostics.availableMemoryBytes == Lab.deviceAvailableMemory)
        #expect(diagnostics.freeDiskBytes == Lab.deviceFreeDisk)
        #expect(diagnostics.writableDiskBytes == Lab.deviceWritableDisk)
        #expect(diagnostics.batteryState == "unplugged")
        #expect(diagnostics.workoutSessionState == "running")
        #expect(diagnostics.memoryWarningCount == 0)
        #expect(diagnostics.motionStatus.isEmpty == false)

        // The server heard from the session while it was alive.
        await session.checkpointer.settlePendingHeartbeat()
        let heartbeat = try #require(lab.heartbeats.published.first)
        #expect(heartbeat.heartbeat.state == .open)
        #expect(heartbeat.heartbeat.mode == mode.draftKind)
        #expect(heartbeat.userId == Lab.userId)

        lab.simulateProcessDeath(session)
        // Asked about this session, not the whole process: other suites run their own sessions
        // beside this one and the registries are process-wide.
        #expect(LiveClimbSessionCoordinator.shared.activeViewModel(sessionID: draft.sessionID) == nil)
        #expect(ActiveRoutineSessionCoordinator.shared.activeViewModel(sessionID: draft.sessionID) == nil)
        #expect(ActiveHeadphoneWorkoutRuntimeRegistry.shared.isActive(draft) == false)
        let found = try #require(try lab.draftStore.activeDraft(in: lab.context))
        #expect(found.id == draft.id)
    }

    @Test("A heartbeat refused at the low-disk floor is recorded and the climb keeps counting", arguments: Mode.allCases)
    func heartbeatRefusedAtTheFloorIsRecordedAndTheSessionKeepsCheckpointing(mode: Mode) async throws {
        let lab = try Lab(mode: mode)
        // The real repository throws this before Firestore is asked (`FirestoreAttemptHeartbeatRepository`);
        // the session has to treat it as a report that was not sent, nothing more.
        lab.heartbeats.refusal = FirestoreLowDiskRefusal(availableBytes: 0)
        let session = try lab.startedSession()
        lab.run(session, seconds: 62)
        await session.checkpointer.settlePendingHeartbeat()

        #expect(lab.heartbeats.published.isEmpty)
        let draft = try #require(try lab.draftStore.activeDraft(in: lab.context))
        #expect(draft.steps == 66, "the refusal costs the climb nothing")
        #expect(draft.status == .recording)
        let failures = lab.diagnostics.recentEvents().filter { $0.name == "attempt_heartbeat_publish_failed" }
        #expect(failures.isEmpty == false, "every due heartbeat was refused, and each refusal is on the record")
        #expect(failures.allSatisfy { $0.details["session_id"] == draft.sessionID })
        #expect(failures.allSatisfy { $0.details["error"]?.contains("low-disk floor") == true })

        // The phone has room again: the next due heartbeat is simply sent, nothing was queued.
        lab.heartbeats.refusal = nil
        lab.run(session, seconds: 62, from: 63)
        await session.checkpointer.settlePendingHeartbeat()
        let published = try #require(lab.heartbeats.published.last)
        #expect(published.heartbeat.state == .open)
        #expect(published.heartbeat.mode == mode.draftKind)
        #expect(published.heartbeat.steps >= 66)
        #expect(lab.heartbeats.published.count <= 2, "at most the heartbeats due in a minute; nothing refused was replayed")
    }

    // MARK: - 2. The next launch resumes by itself and credits the gap

    @Test("Nineteen minutes later the next launch resumes the session, credits the gap, and records one interruption", arguments: Mode.allCases)
    func nextLaunchAutoResumesWithTheGapCredited(mode: Mode) async throws {
        let lab = try Lab(mode: mode)
        let session = try lab.startedSession()
        lab.run(session, seconds: 62)
        let draft = try #require(try lab.draftStore.activeDraft(in: lab.context))
        lab.simulateProcessDeath(session)

        // The next launch: 11:41:21Z, the phone never rebooted.
        lab.clock.now = Self.recoveryShownAt
        let assessment = lab.recovery.assess(draft)
        #expect(assessment.plan == .autoResume)
        #expect(assessment.lossReason == .unknown, "a quiet death with headroom left is a force-quit or a silent jetsam")
        #expect(assessment.gapMinutes == 19)
        #expect(assessment.gapIsCreditable)

        let resumption = try lab.recovery.resume(draft, modelContext: lab.context, assessment: assessment)

        // The draft now carries the dead time, as an interruption rather than as silence.
        #expect(Int(draft.durationSeconds) == 1_227, "credited through the resume: 11:41:21 - 11:20:54")
        #expect(draft.steps == 66, "nothing was counted, so nothing is credited in steps")
        #expect(draft.trackingIntegrity.interruptionCount == 1)
        #expect(Int(draft.trackingIntegrity.longestUnavailableDuration) == 1_227 - 62)
        #expect(draft.lastCheckpointAt == Self.recoveryShownAt)

        // The session is counting again from the credited clock, with the notice up.
        switch resumption.session {
        case .liveClimb(let viewModel):
            #expect(mode != .routine)
            #expect(viewModel.isRecording)
            let resumeState = try #require(lab.resumedMotion.lastResumeState)
            #expect(Int(resumeState.duration) == 1_227)
            #expect(resumeState.steps == 66)
            #expect(resumeState.startedAt == Self.goAt)
            let notice = try #require(viewModel.resumeNotice)
            #expect(notice.gapMinutes == 19)
            #expect(notice.detectedSteps == 66)
            #expect(notice.headline == "Ascend stopped counting for 19 minutes.")
            #expect(LiveClimbSessionCoordinator.shared.activeViewModel(sessionID: draft.sessionID) === viewModel)
        case .routine(let viewModel, _):
            #expect(mode == .routine)
            #expect(viewModel.phase == .active, "a resumed routine skips the countdown")
            let resumeState = try #require(lab.resumedMotion.lastResumeState)
            #expect(Int(resumeState.duration) == 1_227)
            let notice = try #require(viewModel.resumeNotice)
            #expect(notice.gapMinutes == 19)
            #expect(ActiveRoutineSessionCoordinator.shared.activeViewModel(sessionID: draft.sessionID) === viewModel)
            viewModel.stopTimer()
        }

        // Typing the machine's number over the running session credits the steps against the gap.
        let machineSteps = 1_593
        switch resumption.session {
        case .liveClimb(let viewModel):
            lab.resumedMotion.correctionResult = HeadphoneMotionStepCorrection(
                elapsedSeconds: 1_227, detectedSteps: 66, correctedSteps: machineSteps,
                deltaSteps: machineSteps - 66, trackingGapDurationSeconds: 1_165,
                totalUnavailableDurationSeconds: 1_165, interruptionCount: 1
            )
            await viewModel.settleResumeNotice(machineSteps: machineSteps, save: false, modelContext: lab.context)
            #expect(viewModel.resumeNotice == nil)
            #expect(lab.resumedMotion.lastCorrection?.correctedSteps == machineSteps)
            #expect(lab.resumedMotion.lastCorrection?.trackingGapDuration.map { Int($0) } == 1_165)
        case .routine(let viewModel, _):
            lab.resumedMotion.correctionResult = HeadphoneMotionStepCorrection(
                elapsedSeconds: 1_227, detectedSteps: 66, correctedSteps: machineSteps,
                deltaSteps: machineSteps - 66, trackingGapDurationSeconds: 1_165,
                totalUnavailableDurationSeconds: 1_165, interruptionCount: 1
            )
            viewModel.settleResumeNotice(machineSteps: machineSteps, action: .keepCounting)
            #expect(viewModel.resumeNotice == nil)
            #expect(lab.resumedMotion.lastCorrection?.correctedSteps == machineSteps)
        }

        lab.endResumedSession(resumption)
    }

    @Test("The same draft resolved as a whole climb credits the 20:27 completion the climber earned")
    func recoveryStepSyncCreditsTheWork() async throws {
        let lab = try Lab(mode: .liveClimb)
        let draft = try lab.persistedDraft(steps: 66, durationSeconds: 62)

        try lab.draftStore.applyRecoveryStepSync(
            correctedSteps: 1_593,
            to: draft,
            in: lab.context,
            syncedAt: Self.recoveryShownAt
        )

        #expect(draft.steps == 1_593)
        #expect(Int(draft.durationSeconds) == 1_227)
        #expect(draft.trackingIntegrity.interruptionCount == 1)
        #expect(Int(draft.trackingIntegrity.longestUnavailableDuration) == 1_227 - 62)
        #expect(LiveClimbCompletionPolicy.isCompletion(steps: draft.steps, targetStepCount: draft.targetStepCount))

        let workout = ActiveHeadphoneWorkoutDraftSaver.makeRecoveredWorkout(from: draft, deviceModel: "iPhone")
        #expect(workout.steps == 1_593)
        #expect(Int(workout.duration) == 1_227)
        #expect(workout.date == Self.goAt)
        let metadata = try #require(HeadphoneMotionWorkoutMetadata.decode(from: workout.sourceMetadata))
        #expect(metadata.stepCorrections?.count == 1)
        #expect(metadata.stopReason == .interrupted)
    }

    @Test("A draft whose session is already running is never resumed a second time", arguments: Mode.allCases)
    func resumingARunningDraftReturnsTheRunningSession(mode: Mode) async throws {
        let lab = try Lab(mode: mode)
        let session = try lab.startedSession()
        lab.run(session, seconds: 62)
        let draft = try #require(try lab.draftStore.activeDraft(in: lab.context))
        lab.simulateProcessDeath(session)
        lab.clock.now = Self.recoveryShownAt
        let assessment = lab.recovery.assess(draft)

        // The HealthKit relaunch resumes it and the cover adopts it; then the foreground path
        // reaches the same draft.
        let first = try lab.recovery.resume(draft, modelContext: lab.context, assessment: assessment)
        _ = lab.recovery.adopt(draftID: draft.id)
        lab.clock.now = Self.recoveryShownAt.addingTimeInterval(5)
        let second = try lab.recovery.resume(draft, modelContext: lab.context, assessment: assessment)

        switch (first.session, second.session) {
        case (.liveClimb(let started), .liveClimb(let returned)):
            #expect(started === returned)
        case (.routine(let started, _), .routine(let returned, _)):
            #expect(started === returned)
        default:
            Issue.record("the second resume changed the session's mode")
        }
        #expect(draft.trackingIntegrity.interruptionCount == 1, "the gap was credited once")

        lab.endResumedSession(first)
    }

    @Test("The recovery screen's typed count and its Resume credit one gap between them, even retried", arguments: Mode.allCases)
    func promptPathCreditsTheGapOnce(mode: Mode) async throws {
        let lab = try Lab(mode: mode)
        let session = try lab.startedSession()
        lab.run(session, seconds: 62)
        let draft = try #require(try lab.draftStore.activeDraft(in: lab.context))
        lab.simulateProcessDeath(session)

        // Two hours later on a phone that stayed up: past the automatic window, so the screen asks.
        let gap: TimeInterval = 2 * 3_600
        lab.clock.now = Self.goAt.addingTimeInterval(62 + gap)
        let assessment = lab.recovery.assess(draft)
        #expect(assessment.plan == .prompt)

        // Save failed after the typed count landed; the climber then taps Resume Live.
        try lab.recovery.creditGap(to: draft, correctedSteps: 1_400, in: lab.context, at: lab.clock.now)
        lab.clock.now = lab.clock.now.addingTimeInterval(30)
        let resumption = try lab.recovery.resume(
            draft,
            modelContext: lab.context,
            assessment: assessment,
            correctedSteps: 1_500,
            showsNotice: false
        )

        #expect(draft.steps == 1_500)
        #expect(draft.trackingIntegrity.interruptionCount == 1)
        #expect(Int(draft.trackingIntegrity.totalUnavailableDuration) == Int(gap))
        #expect(Int(draft.durationSeconds) == 62, "a gap past the hour is never credited as climbing")

        lab.endResumedSession(resumption)
    }

    @Test("A draft the climber already ended is offered for saving, not restarted")
    func stoppedDraftIsNeverAutoResumed() throws {
        let lab = try Lab(mode: .liveClimb)
        let draft = try lab.persistedDraft(steps: 1_576, durationSeconds: 1_172)
        draft.status = .stopped
        lab.clock.now = draft.lastCheckpointAt.addingTimeInterval(20)

        let assessment = lab.recovery.assess(draft)

        #expect(assessment.plan == .prompt)
        #expect(assessment.climberEndedSession)
    }

    @Test("A draft the climber already ended refuses Resume and credits a typed count through its stop", arguments: Mode.allCases)
    func stoppedDraftRefusesResumeAndKeepsItsClock(mode: Mode) async throws {
        let lab = try Lab(mode: mode)
        let session = try lab.startedSession()
        lab.run(session, seconds: 62)
        let draft = try #require(try lab.draftStore.activeDraft(in: lab.context))
        draft.status = .stopped
        lab.simulateProcessDeath(session)

        // Ten minutes after the climber ended it, the save never having finished.
        lab.clock.now = draft.lastCheckpointAt.addingTimeInterval(600)
        let assessment = lab.recovery.assess(draft)

        #expect(throws: HeadphoneSessionRecoveryError.self) {
            try lab.recovery.resume(draft, modelContext: lab.context, assessment: assessment)
        }
        #expect(LiveClimbSessionCoordinator.shared.activeViewModel(sessionID: draft.sessionID) == nil)
        #expect(ActiveRoutineSessionCoordinator.shared.activeViewModel(sessionID: draft.sessionID) == nil)

        try lab.recovery.creditGap(to: draft, correctedSteps: 80, in: lab.context, at: lab.clock.now)
        #expect(draft.steps == 80)
        #expect(Int(draft.durationSeconds) == 62, "the clock stays where the climber stopped it")
        #expect(draft.trackingIntegrity.interruptionCount == 0)
    }

    @Test("The recovery screen offers no Resume Live for a draft the climber already ended")
    func stoppedDraftRecoveryScreenHasNoResume() async throws {
        let lab = try Lab(mode: .liveClimb)
        let draft = try lab.persistedDraft(steps: 1_500, durationSeconds: 1_172)
        draft.status = .stopped
        lab.clock.now = draft.lastCheckpointAt.addingTimeInterval(600)

        let screen = ActiveHeadphoneWorkoutRecoveryView(draft: draft, onResolved: {}, coordinator: lab.recovery)
            .modelContainer(lab.container)

        try await RenderedScreen.host(screen) { hosted in
            let copy = try await hosted.copy { $0.contains("discard") }
            #expect(copy.contains("you ended this climb at 1,500 steps and 19:32"))
            #expect(copy.contains("save attempt"))
            #expect(copy.contains("discard"))
            #expect(!copy.contains("resume live"))
            #expect(LiveClimbSessionCoordinator.shared.activeViewModel(sessionID: draft.sessionID) == nil)
        }
    }

    @Test("Saving from the recovery screen reports only the gap it credited")
    func recoverySaveReportsTheCreditedGap() throws {
        let lab = try Lab(mode: .liveClimb)
        func saveEvent(_ draft: ActiveHeadphoneWorkoutDraft, typed: Int?) throws -> TelemetryRecord {
            let assessment = lab.recovery.assess(draft)
            let deltaSteps = (typed ?? draft.steps) - draft.steps
            if let typed {
                try lab.recovery.creditGap(to: draft, correctedSteps: typed, in: lab.context, at: lab.clock.now)
            }
            return ActiveHeadphoneWorkoutRecoveryView.promptEvent(
                mode: draft.kind,
                assessment: assessment,
                creditedGapSeconds: lab.recovery.creditedGapSeconds(for: draft),
                deltaSteps: deltaSteps,
                action: .promptSave
            ).record
        }

        // Saved untyped: nothing touched the clock, so nothing was credited.
        let untypedDraft = try lab.persistedDraft(steps: 1_500, durationSeconds: 1_172)
        lab.clock.now = untypedDraft.lastCheckpointAt.addingTimeInterval(600)
        let untyped = try saveEvent(untypedDraft, typed: nil)
        #expect(untyped.parameters["gap_seconds"] == .int(600))
        #expect(untyped.parameters["gap_credited_seconds"] == .int(0))
        #expect(untyped.parameters["gap_source"] == .string("none"))
        #expect(untyped.parameters["action"] == .string("prompt_save"))

        // Saved with the machine's count: the gap was credited from it.
        let typedDraft = try lab.persistedDraft(steps: 1_500, durationSeconds: 1_172)
        lab.clock.now = typedDraft.lastCheckpointAt.addingTimeInterval(600)
        let typed = try saveEvent(typedDraft, typed: 1_593)
        #expect(typed.parameters["gap_seconds"] == .int(600))
        #expect(typed.parameters["gap_credited_seconds"] == .int(600))
        #expect(typed.parameters["gap_source"] == .string("machine"))

        // An auto-resume that credited the gap and then fell back to the screen: saved untyped.
        let fallbackDraft = try lab.persistedDraft(steps: 1_500, durationSeconds: 1_172)
        lab.clock.now = fallbackDraft.lastCheckpointAt.addingTimeInterval(600)
        let assessment = lab.recovery.assess(fallbackDraft)
        try lab.recovery.creditGap(to: fallbackDraft, correctedSteps: nil, in: lab.context, at: lab.clock.now)
        let fallback = ActiveHeadphoneWorkoutRecoveryView.promptEvent(
            mode: fallbackDraft.kind,
            assessment: assessment,
            creditedGapSeconds: lab.recovery.creditedGapSeconds(for: fallbackDraft),
            deltaSteps: 0,
            action: .promptSave
        ).record
        #expect(fallback.parameters["gap_credited_seconds"] == .int(600))
        #expect(fallback.parameters["gap_source"] == .string("wall_clock"))

        // A session the climber ended keeps its stopped clock, typed count or not.
        let endedDraft = try lab.persistedDraft(steps: 1_500, durationSeconds: 1_172)
        endedDraft.status = .stopped
        lab.clock.now = endedDraft.lastCheckpointAt.addingTimeInterval(600)
        let ended = try saveEvent(endedDraft, typed: 1_593)
        #expect(ended.parameters["gap_seconds"] == .int(600))
        #expect(ended.parameters["gap_credited_seconds"] == .int(0))
        #expect(ended.parameters["gap_source"] == .string("none"))
    }

    @Test("The typed-count hint promises the gap credit only to a session Ascend lost")
    func stepSyncHintMatchesWhatSavingCredits() {
        #expect(ActiveHeadphoneWorkoutRecoveryView.stepSyncHint(steps: 1_593, climberEndedSession: false)
            == "Saving credits 1,593 steps and the time since Ascend stopped, with the gap recorded.")
        #expect(ActiveHeadphoneWorkoutRecoveryView.stepSyncHint(steps: 1_593, climberEndedSession: true)
            == "Saving credits 1,593 steps at the time you ended it.")
    }

    @Test("Saving from the resume sheet keeps every step the sensor counted after the resume", arguments: Mode.allCases)
    func resumeSheetKeepsStepsCountedSinceTheResume(mode: Mode) async throws {
        let lab = try Lab(mode: mode)
        let session = try lab.startedSession()
        lab.run(session, seconds: 62)
        let draft = try #require(try lab.draftStore.activeDraft(in: lab.context))
        lab.simulateProcessDeath(session)
        lab.clock.now = Self.recoveryShownAt
        let resumption = try lab.recovery.resume(draft, modelContext: lab.context, assessment: lab.recovery.assess(draft))

        // The phone counted 1,500 across the gap; the climber climbs 40 more while reading the
        // sheet, then accepts the pre-filled number.
        let expected = 66 + 1_500 + 40
        lab.resumedMotion.correctionResult = HeadphoneMotionStepCorrection(
            elapsedSeconds: 1_230, detectedSteps: 106, correctedSteps: expected,
            deltaSteps: expected - 106, trackingGapDurationSeconds: 1_165,
            totalUnavailableDurationSeconds: 1_165, interruptionCount: 1
        )
        switch resumption.session {
        case .liveClimb(let viewModel):
            viewModel.attachPhoneStepEstimate(1_500)
            let notice = try #require(viewModel.resumeNotice)
            #expect(notice.suggestedSteps == 1_566)
            lab.resumedMotion.stepCount += 40
            await viewModel.settleResumeNotice(machineSteps: notice.suggestedSteps, save: false, modelContext: lab.context)
        case .routine(let viewModel, _):
            viewModel.attachPhoneStepEstimate(1_500)
            let notice = try #require(viewModel.resumeNotice)
            #expect(notice.suggestedSteps == 1_566)
            lab.resumedMotion.stepCount += 40
            viewModel.settleResumeNotice(machineSteps: notice.suggestedSteps, action: .save)
        }

        #expect(lab.resumedMotion.lastCorrection?.correctedSteps == expected)

        lab.endResumedSession(resumption)
    }

    @Test("Saving or discarding from the recovery screen closes the server heartbeat")
    func recoveryScreenClosesTheHeartbeat() async throws {
        let lab = try Lab(mode: .liveClimb)
        let draft = try lab.persistedDraft(steps: 66, durationSeconds: 62)

        lab.recovery.publishSessionEnd(for: draft, outcome: .saved)

        for _ in 0..<100 where lab.heartbeats.published.isEmpty {
            await Task.yield()
        }
        let published = try #require(lab.heartbeats.published.last)
        #expect(published.heartbeat.sessionID == draft.sessionID)
        #expect(published.heartbeat.state == .ended)
        #expect(published.heartbeat.outcome == .saved)
    }

    // MARK: - 3. The Lock Screen is honest

    @Test("Every live activity update carries a stale date fifteen seconds ahead")
    func liveActivityContentCarriesAStaleDate() {
        let now = Self.goAt.addingTimeInterval(62)
        let state = LiveClimbActivityAttributes.ContentState(
            steps: 66, rank: 1, rankTotal: 1, ownClimbs: nil, board: .alone,
            durationSeconds: 62, progress: 0.04, status: .recording,
            climbPhotoURLString: nil, updatedAt: now
        )

        let content = LiveClimbActivityManager.shared.makeLiveContent(state: state, now: now)

        #expect(content.staleDate == now.addingTimeInterval(15))
        #expect(LiveClimbActivityStalenessPolicy.staleAfter == 15)
        #expect(LiveClimbActivityStalenessPolicy.staleDate(publishedAt: now) == now.addingTimeInterval(15))
    }

    // MARK: - 4. A phone that was off lands on the recovery screen, machine count first

    @Test("A phone that died mid-climb and came back two hours later gets the recovery screen, led by the machine's count", arguments: Mode.allCases)
    func poweredOffPhoneLandsOnTheReorderedRecoveryScreen(mode: Mode) async throws {
        let lab = try Lab(mode: mode)
        let session = try lab.startedSession()
        lab.run(session, seconds: 62)
        let draft = try #require(try lab.draftStore.activeDraft(in: lab.context))
        lab.simulateProcessDeath(session)

        // Two hours later, on a phone that has been up for twenty minutes: it rebooted.
        lab.clock.now = Self.goAt.addingTimeInterval(62 + 2 * 3_600)
        lab.clock.systemUptime = 20 * 60
        let assessment = lab.recovery.assess(draft)
        #expect(assessment.plan == .prompt)
        #expect(assessment.lossReason == .phoneOff)
        #expect(assessment.gapIsCreditable == false)

        let screen = ActiveHeadphoneWorkoutRecoveryView(draft: draft, onResolved: {}, coordinator: lab.recovery)
            .modelContainer(lab.container)

        try await RenderedScreen.host(screen) { hosted in
            let copy = try await hosted.copy { $0.contains("discard") }
            #expect(copy.contains("ascend stopped counting."))
            #expect(copy.contains("your phone was off 2 hours ago, at 66 steps and 1:02"))
            #expect(copy.contains("machine's current steps"))
            #expect(copy.contains("last counted 66"))
            #expect(copy.contains("resume live"))
            #expect(copy.contains("discard"))
            #expect(!copy.contains("resume live?"), "the old headline led with resuming")

            let saveTitle = mode == .liveClimb ? "Save Attempt" : (mode == .justClimb ? "Save Session" : "Save Routine")
            let save = try #require(try await Self.buttonFrame(labelled: saveTitle, in: hosted))
            let resume = try #require(try await Self.buttonFrame(labelled: "Resume Live", in: hosted))
            let discard = try #require(try await Self.buttonFrame(labelled: "Discard", in: hosted))
            #expect(save.minY < resume.minY, "Save leads")
            #expect(resume.minY < discard.minY, "Discard is last")

            try hosted.photograph(named: "recovery-screen-phone-off-\(mode.rawValue)")
        }
    }

    // MARK: - 4b. A phone that ran out of space says so

    /// 2026-10-23 again, as it really was: no blocks left, so neither crash reporter could write
    /// its report and the next launch reads `crashedLastRun == false`. Only the last checkpoint's
    /// `statfs` reading can name it, and a gigabyte iOS could purge must not hide it.
    @Test("A full phone's session resumes nineteen minutes later and the sheet says the phone ran out of space", arguments: Mode.allCases)
    func fullPhoneResumeSheetNamesTheSpace(mode: Mode) async throws {
        let lab = try Lab(mode: mode)
        lab.volume.importantUsageBytes = 1_024 * 1_048_576
        lab.volume.writableBytes = 0
        let session = try lab.startedSession()
        lab.run(session, seconds: 62)
        let draft = try #require(try lab.draftStore.activeDraft(in: lab.context))
        lab.simulateProcessDeath(session)
        #expect(draft.checkpointDiagnostics?.writableDiskBytes == 0, "the checkpoint persisted the statfs reading")
        #expect(draft.checkpointDiagnostics?.freeDiskBytes == Int64(1_024 * 1_048_576), "the important-usage figure is kept beside it")

        lab.clock.now = Self.recoveryShownAt
        let assessment = lab.recovery.assess(draft)
        #expect(assessment.lossReason == .outOfDiskSpace)
        #expect(assessment.plan == .autoResume)

        let resumption = try lab.recovery.resume(draft, modelContext: lab.context, assessment: assessment)
        let notice: HeadphoneSessionResumeNotice
        switch resumption.session {
        case .liveClimb(let viewModel):
            notice = try #require(viewModel.resumeNotice)
        case .routine(let viewModel, _):
            notice = try #require(viewModel.resumeNotice)
        }
        #expect(notice.explanation.hasPrefix("Your phone ran out of space (0 MB free) and the climb kept going without it."))

        let sheet = HeadphoneSessionResumeSheet(notice: notice, sessionLabel: "climb", onSave: { _ in }, onKeepCounting: { _ in })
            .themedBackground()
        try await RenderedScreen.host(sheet) { hosted in
            let copy = try await hosted.copy { $0.contains("ran out of space") }
            #expect(copy.contains("ascend stopped counting for 19 minutes."))
            #expect(copy.contains("your phone ran out of space (0 mb free) and the climb kept going without it."))
            try hosted.photograph(named: "resume-sheet-out-of-space-\(mode.rawValue)")
        }
        lab.endResumedSession(resumption)
    }

    @Test("A full phone found two hours later lands on the recovery screen naming the space it had left")
    func fullPhoneRecoveryScreenNamesTheSpace() async throws {
        let lab = try Lab(mode: .liveClimb)
        lab.volume.importantUsageBytes = 1_024 * 1_048_576
        lab.volume.writableBytes = 12 * 1_048_576
        let session = try lab.startedSession()
        lab.run(session, seconds: 62)
        let draft = try #require(try lab.draftStore.activeDraft(in: lab.context))
        lab.simulateProcessDeath(session)

        lab.clock.now = Self.goAt.addingTimeInterval(62 + 2 * 3_600)
        let assessment = lab.recovery.assess(draft)
        #expect(assessment.plan == .prompt)
        #expect(assessment.lossReason == .outOfDiskSpace)

        let screen = ActiveHeadphoneWorkoutRecoveryView(draft: draft, onResolved: {}, coordinator: lab.recovery)
            .modelContainer(lab.container)
        try await RenderedScreen.host(screen) { hosted in
            let copy = try await hosted.copy { $0.contains("discard") }
            #expect(copy.contains("your phone ran out of space (12 mb free) 2 hours ago, at 66 steps and 1:02"))
            try hosted.photograph(named: "recovery-screen-out-of-space-liveClimb")
        }
    }

    @Test("A checkpoint with no statfs reading and a low important-usage figure is not called a full phone")
    func checkpointWithoutAStatfsReadingIsNotCalledFull() async throws {
        let lab = try Lab(mode: .liveClimb)
        lab.volume.importantUsageBytes = 12 * 1_048_576
        lab.volume.writableBytes = nil
        let session = try lab.startedSession()
        lab.run(session, seconds: 62)
        let draft = try #require(try lab.draftStore.activeDraft(in: lab.context))
        lab.simulateProcessDeath(session)

        lab.clock.now = Self.goAt.addingTimeInterval(62 + 2 * 3_600)
        #expect(lab.recovery.assess(draft).lossReason == .unknown)

        let screen = ActiveHeadphoneWorkoutRecoveryView(draft: draft, onResolved: {}, coordinator: lab.recovery)
            .modelContainer(lab.container)
        try await RenderedScreen.host(screen) { hosted in
            let copy = try await hosted.copy { $0.contains("discard") }
            #expect(copy.contains("ascend was closed 2 hours ago"))
            #expect(!copy.contains("out of space"))
            try hosted.photograph(named: "recovery-screen-no-statfs-reading-liveClimb")
        }
    }

    @Test("The simulator's real device diagnostics answer the statfs reading the planner decides on")
    func realDeviceDiagnosticsReadStatfs() throws {
        let live = LiveHeadphoneSessionDeviceDiagnostics()
        let writable = try #require(live.writableDiskBytes())
        var stats = statfs()
        #expect(statfs(NSHomeDirectory(), &stats) == 0)
        let expected = Int64(clamping: stats.f_bavail) * Int64(stats.f_bsize)
        #expect(abs(writable - expected) < 64 * 1_048_576, "the same statfs figure, read moments apart")
        #expect(live.freeDiskBytes() != nil)
        print("LIVE_DISK_READING writable_bytes=\(writable) important_usage_bytes=\(live.freeDiskBytes() ?? -1) home=\(NSHomeDirectory())")
    }

    // MARK: - 5. A refused checkpoint goes to the file, loudly

    @Test("A checkpoint the store refuses records a diagnostic with the free disk and lands in the JSON fallback, which the next launch reads back", arguments: Mode.allCases)
    func refusedCheckpointFallsBackToTheFile(mode: Mode) async throws {
        let lab = try Lab(mode: mode)
        let session = try lab.startedSession()
        lab.run(session, seconds: 30)
        let draft = try #require(try lab.draftStore.activeDraft(in: lab.context))
        #expect(draft.steps == 32)

        // The disk fills; every save from here is refused.
        lab.storeRefusesSaves = true
        lab.run(session, seconds: 32, from: 31)

        #expect(session.checkpointer.lastOutcome == .fellBackToFile)
        #expect(session.checkpointer.fallbackCount >= 1)
        let failure = try #require(lab.diagnostics.recentEvents().first { $0.name == "active_headphone_draft_checkpoint_failed" })
        #expect(failure.level == .error)
        #expect(failure.details["error"] == "The disk is full.")
        #expect(failure.details["free_disk_mb"] == String(Lab.deviceFreeDisk / 1_048_576))
        let fallback = try #require(try lab.fallbackStore.read(draftID: draft.id))
        #expect(fallback.steps == 66)
        #expect(Int(fallback.durationSeconds) == 62)

        // The dead process's store row froze at its last accepted save; the next launch does
        // not read that number, it reads the file.
        lab.simulateProcessDeath(session)
        lab.storeRefusesSaves = false
        lab.context.rollback()
        let frozen = try #require(try lab.fetchDraftRow(id: draft.id))
        #expect(frozen.steps == 32, "the row stopped where the store stopped accepting writes")

        let restored = try #require(try lab.draftStore.activeDraft(in: lab.context))
        #expect(restored.id == draft.id)
        #expect(restored.steps == 66)
        #expect(Int(restored.durationSeconds) == 62)
        #expect(try lab.fallbackStore.read(draftID: draft.id) == nil, "the file is consumed once the store accepted it")
        #expect(lab.diagnostics.recentEvents().contains { $0.name == "active_headphone_draft_fallback_restored" })
    }

    // MARK: - Lab

    /// The on-screen frame of the button with exactly this label - a paragraph that mentions the
    /// same word is not the button.
    private static func buttonFrame(labelled label: String, in hosted: HostedScreen) async throws -> CGRect? {
        let elements = try await hosted.elements { elements in
            elements.contains { Self.isButton($0, labelled: label) }
        }
        return elements.first { Self.isButton($0, labelled: label) }?.accessibilityFrame
    }

    private static func isButton(_ element: NSObject, labelled label: String) -> Bool {
        element.accessibilityTraits.contains(.button) &&
            (element.accessibilityLabel ?? "").caseInsensitiveCompare(label) == .orderedSame
    }

    private static func stepsAt(second: Int) -> Int {
        Int((Double(second) * 66.0 / 62.0).rounded())
    }

    /// A clock every collaborator reads, so a test can move the whole phone forward.
    @MainActor
    final class Clock {
        var now: Date
        var systemUptime: TimeInterval = 7 * 24 * 3_600

        init(now: Date) {
            self.now = now
        }
    }

    @MainActor
    final class RecordedDeviceDiagnostics: HeadphoneSessionDeviceDiagnosticsProviding {
        let clock: Clock
        let volume: Volume
        init(clock: Clock, volume: Volume) {
            self.clock = clock
            self.volume = volume
        }
        func availableMemoryBytes() -> Int64? { Lab.deviceAvailableMemory }
        func freeDiskBytes() -> Int64? { volume.importantUsageBytes }
        func writableDiskBytes() -> Int64? { volume.writableBytes }
        func batteryLevel() -> Double? { 0.84 }
        func batteryState() -> String { "unplugged" }
        func systemUptime() -> TimeInterval { clock.systemUptime }
        func processUptime() -> TimeInterval { 90 }
    }

    /// The phone's volume as the two disk readings see it, settable so a test can fill it.
    @MainActor
    final class Volume {
        var importantUsageBytes: Int64? = Lab.deviceFreeDisk
        var writableBytes: Int64? = Lab.deviceWritableDisk
    }

    final class RecordingHeartbeatPublisher: AttemptHeartbeatPublishing, @unchecked Sendable {
        struct Published { let heartbeat: AttemptHeartbeat; let userId: String }
        private let lock = NSLock()
        private var _published: [Published] = []
        private var _refusal: (any Error)?
        var published: [Published] { lock.withLock { _published } }
        /// Set by a test to have every publish fail the way the real repository does on a
        /// volume at the low-disk floor; nil publishes.
        var refusal: (any Error)? {
            get { lock.withLock { _refusal } }
            set { lock.withLock { _refusal = newValue } }
        }
        func publish(_ heartbeat: AttemptHeartbeat, userId: String) async throws {
            if let refusal = lock.withLock({ _refusal }) { throw refusal }
            lock.withLock { _published.append(Published(heartbeat: heartbeat, userId: userId)) }
        }
    }

    enum StoreRefusal: LocalizedError {
        case diskFull
        var errorDescription: String? { "The disk is full." }
    }

    /// Everything a session runs on, with the sensor, the clock, the store's willingness to save,
    /// the device readings and the server all under the test's hand.
    @MainActor
    final class Lab {
        static let userId = "ZVm34nndUxd9oHF7XnZ4cQmFK6Z2"
        static let deviceAvailableMemory: Int64 = 1_200 * 1_048_576
        static let deviceFreeDisk: Int64 = 8 * 1_024 * 1_048_576
        static let deviceWritableDisk: Int64 = 6 * 1_024 * 1_048_576

        let mode: Mode
        let container: ModelContainer
        let context: ModelContext
        let clock: Clock
        let volume = Volume()
        let defaults: UserDefaults
        let fallbackStore: ActiveHeadphoneWorkoutDraftFallbackStore
        let draftStore: ActiveHeadphoneWorkoutDraftStore
        let diagnostics: AppDiagnosticsRecorder
        let heartbeats = RecordingHeartbeatPublisher()
        let climbService: ClimbService
        let background = FakeLiveClimbBackgroundSession()
        let memoryMonitor = AppMemoryPressureMonitor(notificationCenter: NotificationCenter())
        let motion = FakeHeadphoneMotionSession()
        let resumedMotion = FakeHeadphoneMotionSession()
        let routine: Routine
        var storeRefusesSaves = false
        private(set) var recovery: HeadphoneSessionRecoveryCoordinator!
        private var retained: [AnyObject] = []

        init(mode: Mode) throws {
            self.mode = mode
            container = try RetainedModelContainer.inMemory(
                for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self,
                ClimbAttempt.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self,
                ActiveHeadphoneWorkoutDraft.self, Routine.self, RoutineFolder.self
            )
            context = container.mainContext
            clock = Clock(now: HeadphoneSessionSurvivesProcessDeathTests.goAt)
            let suite = "survives-\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suite)!
            fallbackStore = ActiveHeadphoneWorkoutDraftFallbackStore(
                directoryURL: FileManager.default.temporaryDirectory.appending(path: suite)
            )
            diagnostics = AppDiagnosticsRecorder(userDefaults: defaults)
            draftStore = ActiveHeadphoneWorkoutDraftStore(
                userDefaults: defaults,
                fallbackStore: fallbackStore,
                diagnostics: diagnostics
            )
            climbService = ClimbService(catalogRepository: StubClimbCatalogRepository(climbs: [Lab.climb]))
            routine = Routine(
                id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
                name: "Pyramid Climb",
                source: .builtin,
                intervals: [
                    RoutineInterval(duration: 600, intensityValue: 8, order: 0),
                    RoutineInterval(duration: 900, intensityValue: 12, order: 1),
                    RoutineInterval(duration: 600, intensityValue: 16, order: 2)
                ],
                templateId: "pyramid_climb"
            )
            context.insert(routine)
            try context.save()
            seedResumeStateIntoFake(resumedMotion)

            recovery = HeadphoneSessionRecoveryCoordinator(
                draftStore: draftStore,
                featureFlags: RemoteFeatureFlagStore(),
                stepEstimator: NoPhoneStepEstimator(),
                systemUptime: { [clock] in clock.systemUptime },
                crashedLastRun: { false },
                now: { [clock] in clock.now },
                climbLookup: { [climbService] in try? climbService.climb(for: $0) },
                makeLiveClimbSession: { [unowned self] climb, draft, notice in
                    makeLiveClimbViewModel(climb: climb, motion: resumedMotion, recoveredDraft: draft, notice: notice)
                },
                makeJustClimbSession: { [unowned self] draft, notice in
                    makeJustClimbViewModel(motion: resumedMotion, recoveredDraft: draft, notice: notice)
                },
                makeRoutineSession: { [unowned self] routine, draft, notice in
                    makeRoutineViewModel(routine: routine, motion: resumedMotion, recoveredDraft: draft, notice: notice)
                },
                makeCheckpointer: { [unowned self] in makeCheckpointer() }
            )
        }

        func makeCheckpointer() -> HeadphoneSessionCheckpointer {
            HeadphoneSessionCheckpointer(
                draftStore: draftStore,
                fallbackStore: fallbackStore,
                deviceDiagnostics: RecordedDeviceDiagnostics(clock: clock, volume: volume),
                memoryMonitor: memoryMonitor,
                backgroundSession: background,
                heartbeatPublisher: heartbeats,
                currentUserId: { Lab.userId },
                featureFlags: RemoteFeatureFlagStore(),
                diagnostics: diagnostics,
                save: { [unowned self] modelContext in
                    if storeRefusesSaves { throw StoreRefusal.diskFull }
                    try modelContext.save()
                },
                now: { [clock] in clock.now }
            )
        }

        /// The real service seeds its counters from the resume state inside `startRecording`
        /// (`HeadphoneMotionSessionService.startRecording`); the fake has to do the same, or the
        /// forced start checkpoint would overwrite the draft with zeros.
        private func seedResumeStateIntoFake(_ fake: FakeHeadphoneMotionSession) {
            fake.onStartRecording = { [unowned fake] in
                fake.duration = fake.lastResumeState?.duration ?? 0
                fake.stepCount = fake.lastResumeState?.steps ?? 0
                fake.sampleCount = fake.lastResumeState?.sampleCount ?? 0
                fake.trackingIntegrity = fake.lastResumeState?.trackingIntegrity ?? .verified
            }
        }

        func makeLiveClimbViewModel(
            climb: Climb,
            motion: FakeHeadphoneMotionSession,
            recoveredDraft: ActiveHeadphoneWorkoutDraft? = nil,
            notice: HeadphoneSessionResumeNotice? = nil
        ) -> LiveClimbSessionViewModel {
            let viewModel = LiveClimbSessionViewModel(
                climb: climb,
                motionSession: motion,
                climbService: climbService,
                leaderboardService: StubLiveReplayLeaderboardService(),
                backgroundSessionService: background,
                draftStore: draftStore,
                liveActivitySessionID: recoveredDraft?.sessionID ?? UUID().uuidString,
                recoveredDraft: recoveredDraft,
                resumeNotice: notice,
                checkpointer: makeCheckpointer(),
                now: { [clock] in clock.now }
            )
            retained.append(viewModel)
            return viewModel
        }

        func makeJustClimbViewModel(
            motion: FakeHeadphoneMotionSession,
            recoveredDraft: ActiveHeadphoneWorkoutDraft? = nil,
            notice: HeadphoneSessionResumeNotice? = nil
        ) -> LiveClimbSessionViewModel {
            let viewModel = LiveClimbSessionViewModel(
                justClimbGoal: JustClimbGoal(kind: .steps, durationMinutes: 20, stepCount: 1_576),
                motionSession: motion,
                climbService: climbService,
                leaderboardService: StubLiveReplayLeaderboardService(),
                backgroundSessionService: background,
                draftStore: draftStore,
                liveActivitySessionID: recoveredDraft?.sessionID ?? UUID().uuidString,
                recoveredDraft: recoveredDraft,
                resumeNotice: notice,
                checkpointer: makeCheckpointer(),
                now: { [clock] in clock.now }
            )
            retained.append(viewModel)
            return viewModel
        }

        func makeRoutineViewModel(
            routine: Routine,
            motion: FakeHeadphoneMotionSession,
            recoveredDraft: ActiveHeadphoneWorkoutDraft? = nil,
            notice: HeadphoneSessionResumeNotice? = nil
        ) -> ActiveRoutineViewModel {
            let viewModel = ActiveRoutineViewModel(
                routine: routine,
                leaderboardService: StubLiveReplayLeaderboardService(),
                motionSession: motion,
                backgroundSessionService: background,
                draftStore: draftStore,
                recoveredDraft: recoveredDraft,
                resumeNotice: notice,
                checkpointer: makeCheckpointer(),
                now: { [clock] in clock.now }
            )
            retained.append(viewModel)
            return viewModel
        }

        /// A running session for this lab's mode: GO has happened, the sensor is recording.
        func startedSession() throws -> Session {
            switch mode {
            case .liveClimb:
                let viewModel = makeLiveClimbViewModel(climb: Lab.climb, motion: motion)
                viewModel.start(modelContext: context)
                motion.status = .recording
                try #require(viewModel.isRecording)
                return .liveClimb(viewModel)
            case .justClimb:
                let viewModel = makeJustClimbViewModel(motion: motion)
                viewModel.start(modelContext: context)
                motion.status = .recording
                try #require(viewModel.isRecording)
                return .liveClimb(viewModel)
            case .routine:
                let viewModel = makeRoutineViewModel(routine: routine, motion: motion)
                viewModel.startSession(modelContext: context, skipsCountdown: true)
                viewModel.stopTimer()
                motion.status = .recording
                try #require(viewModel.phase == .active)
                return .routine(viewModel)
            }
        }

        /// Steady stepping at the pace the screenshot's average implies, one second per tick,
        /// through the production tick and the scene-phase checkpoint at the end.
        func run(_ session: Session, seconds: Int, from firstSecond: Int = 1) {
            let lastSecond = firstSecond + seconds - 1
            for second in firstSecond...lastSecond {
                clock.now = HeadphoneSessionSurvivesProcessDeathTests.goAt.addingTimeInterval(TimeInterval(second))
                motion.duration = TimeInterval(second)
                motion.stepCount = HeadphoneSessionSurvivesProcessDeathTests.stepsAt(second: second)
                motion.sampleCount = second * 50
                switch session {
                case .liveClimb(let viewModel):
                    viewModel.recordLiveSplitSampleAndCheckpoint()
                    if second % 10 == 0 { motion.emitStepSample() }
                case .routine(let viewModel):
                    viewModel.handleTick(at: clock.now)
                    viewModel.checkpointer.runAutomaticCheckpoint()
                }
            }
            // What the scene-phase hook writes the moment the app leaves the foreground.
            switch session {
            case .liveClimb(let viewModel):
                viewModel.checkpointForLifecycleChange()
            case .routine(let viewModel):
                viewModel.checkpointForLifecycleChange()
            }
        }

        /// A draft exactly as SwiftData held it at the climber's last persisted checkpoint.
        func persistedDraft(steps: Int, durationSeconds: TimeInterval) throws -> ActiveHeadphoneWorkoutDraft {
            let draft = ActiveHeadphoneWorkoutDraft(
                sessionID: UUID().uuidString,
                kind: .liveClimb,
                startedAt: HeadphoneSessionSurvivesProcessDeathTests.goAt,
                title: Lab.climb.name,
                subtitle: Lab.climb.displayLocation,
                workoutName: "\(Lab.climb.name) Live Climb",
                targetStepCount: Lab.climb.referenceStepCount,
                targetDurationSeconds: nil,
                climbId: Lab.climb.id
            )
            var recorder = LiveClimbStepTimelineRecorder(intervalSeconds: 10)
            recorder.record(elapsedSeconds: 0, cumulativeSteps: 0, source: .headphoneMotion)
            for second in stride(from: 10, through: 60, by: 10) {
                recorder.record(
                    elapsedSeconds: second,
                    cumulativeSteps: HeadphoneSessionSurvivesProcessDeathTests.stepsAt(second: second),
                    source: .headphoneMotion
                )
            }
            draft.applyCheckpoint(
                steps: steps,
                durationSeconds: durationSeconds,
                sampleCount: Int(durationSeconds) * 50,
                splitCurve: recorder.curve,
                trackingIntegrity: .verified,
                stepCorrections: [],
                checkpointedAt: HeadphoneSessionSurvivesProcessDeathTests.goAt.addingTimeInterval(durationSeconds)
            )
            try draftStore.insert(draft, in: context)
            return draft
        }

        func fetchDraftRow(id: UUID) throws -> ActiveHeadphoneWorkoutDraft? {
            try context.fetch(FetchDescriptor<ActiveHeadphoneWorkoutDraft>(predicate: #Predicate { $0.id == id })).first
        }

        /// Everything a dead process forgets: the in-memory registries that gate the recovery
        /// screen and the running view model. The draft row, its pointer in UserDefaults and any
        /// fallback file are what survive.
        func simulateProcessDeath(_ session: Session) {
            switch session {
            case .liveClimb(let viewModel):
                viewModel.checkpointer.stopAutomaticCheckpoints()
                LiveClimbSessionCoordinator.shared.clearIfActive(sessionID: viewModel.liveActivitySessionID)
                ActiveHeadphoneWorkoutRuntimeRegistry.shared.markInactive(viewModel.checkpointer.activeDraft)
                retained.removeAll { $0 === viewModel }
            case .routine(let viewModel):
                viewModel.stopTimer()
                viewModel.checkpointer.stopAutomaticCheckpoints()
                ActiveRoutineSessionCoordinator.shared.clearIfActive(sessionID: viewModel.sessionID)
                ActiveHeadphoneWorkoutRuntimeRegistry.shared.markInactive(viewModel.checkpointer.activeDraft)
                retained.removeAll { $0 === viewModel }
            }
        }

        /// A resumed session is process-wide state; the next test must not inherit it.
        func endResumedSession(_ resumption: HeadphoneSessionResumption) {
            switch resumption.session {
            case .liveClimb(let viewModel):
                viewModel.checkpointer.stopAutomaticCheckpoints()
                LiveClimbSessionCoordinator.shared.clearIfActive(sessionID: viewModel.liveActivitySessionID)
                ActiveHeadphoneWorkoutRuntimeRegistry.shared.markInactive(viewModel.checkpointer.activeDraft)
            case .routine(let viewModel, _):
                viewModel.stopTimer()
                viewModel.checkpointer.stopAutomaticCheckpoints()
                ActiveRoutineSessionCoordinator.shared.clearIfActive(sessionID: viewModel.sessionID)
                ActiveHeadphoneWorkoutRuntimeRegistry.shared.markInactive(viewModel.checkpointer.activeDraft)
            }
            _ = recovery.adopt(draftID: resumption.draftID)
        }

        static let climb = Climb(
            id: "empire-state-building",
            name: "Empire State Building",
            city: "New York",
            country: "United States",
            continent: "North America",
            latitude: 40.748_4,
            longitude: -73.985_7,
            totalHeightMeters: 443,
            totalHeightFeet: 1_454,
            realClimbableHeightMeters: nil,
            realClimbableHeightFeet: nil,
            totalSteps: 2_437,
            realStairCount: 1_576,
            calculatedFloors: 86,
            category: "skyscraper",
            tier: .gold,
            tags: [],
            funFact: "Fact",
            sourceURL: "https://example.com",
            imageSetVersion: 1,
            releaseState: .available
        )
    }

    @MainActor
    enum Session {
        case liveClimb(LiveClimbSessionViewModel)
        case routine(ActiveRoutineViewModel)

        var checkpointer: HeadphoneSessionCheckpointer {
            switch self {
            case .liveClimb(let viewModel): viewModel.checkpointer
            case .routine(let viewModel): viewModel.checkpointer
            }
        }
    }
}
