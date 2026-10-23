import Foundation
@preconcurrency import Sentry
import SwiftData

/// A session this process has already restarted from a draft, waiting for a screen to show it.
@MainActor
struct HeadphoneSessionResumption {
    enum Session {
        case liveClimb(LiveClimbSessionViewModel)
        case routine(ActiveRoutineViewModel, Routine)
    }

    let draftID: UUID
    let sessionID: String
    let session: Session
    let assessment: HeadphoneSessionRecoveryAssessment
}

enum HeadphoneSessionRecoveryError: LocalizedError {
    case climbUnavailable
    case routineUnavailable
    case sessionEnded
    case sessionFailedToStart(String)

    var errorDescription: String? {
        switch self {
        case .climbUnavailable:
            return "This climb is no longer available."
        case .routineUnavailable:
            return "This routine is no longer available. Save the attempt or discard it."
        case .sessionEnded:
            return "You already ended this session. Save it or discard it."
        case .sessionFailedToStart(let message):
            return message
        }
    }
}

/// Turns a draft a dead process left behind back into a running session, for every mode.
///
/// One implementation: the recovery screen, the Live Activity tap and the HealthKit background
/// relaunch all come here, assess the draft the same way (`HeadphoneSessionRecoveryPlanner`),
/// credit the gap the same way (`ActiveHeadphoneWorkoutDraftStore.creditTrackingGap`), restart the
/// session for its mode, and report `live_climb_session_lost` once per draft. A session started
/// with no screen is kept in `resumptions` until a screen adopts it.
@MainActor
@Observable
final class HeadphoneSessionRecoveryCoordinator {
    static let shared = HeadphoneSessionRecoveryCoordinator()

    private(set) var resumptions: [UUID: HeadphoneSessionResumption] = [:]
    @ObservationIgnored private var reportedLostDraftIDs: Set<UUID> = []
    /// The checkpoint each draft's gap was last credited from, so the same gap is never credited
    /// twice. A session that runs again moves the checkpoint, and its next death is a new gap.
    @ObservationIgnored private var gapCreditedCheckpoints: [UUID: Date] = [:]

    private let draftStore: ActiveHeadphoneWorkoutDraftStore
    private let featureFlags: RemoteFeatureFlagStore
    private let stepEstimator: any PhoneStepEstimating
    private let systemUptime: () -> TimeInterval
    private let crashedLastRun: () -> Bool
    private let now: () -> Date
    private let makeLiveClimbSession: @MainActor (Climb, ActiveHeadphoneWorkoutDraft, HeadphoneSessionResumeNotice?) -> LiveClimbSessionViewModel
    private let makeJustClimbSession: @MainActor (ActiveHeadphoneWorkoutDraft, HeadphoneSessionResumeNotice?) -> LiveClimbSessionViewModel
    private let makeRoutineSession: @MainActor (Routine, ActiveHeadphoneWorkoutDraft, HeadphoneSessionResumeNotice?) -> ActiveRoutineViewModel
    private let climbLookup: @MainActor (String) -> Climb?
    private let makeCheckpointer: @MainActor () -> HeadphoneSessionCheckpointer

    init(
        draftStore: ActiveHeadphoneWorkoutDraftStore = ActiveHeadphoneWorkoutDraftStore(),
        featureFlags: RemoteFeatureFlagStore = .shared,
        stepEstimator: any PhoneStepEstimating = CMPedometerStepEstimator.shared,
        systemUptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        crashedLastRun: @escaping () -> Bool = { SentrySDK.isEnabled && SentrySDK.lastRunStatus == .didCrash },
        now: @escaping () -> Date = Date.init,
        climbLookup: @escaping @MainActor (String) -> Climb? = { try? ClimbService.shared.climb(for: $0) },
        makeLiveClimbSession: @escaping @MainActor (Climb, ActiveHeadphoneWorkoutDraft, HeadphoneSessionResumeNotice?) -> LiveClimbSessionViewModel = { climb, draft, notice in
            LiveClimbSessionViewModel(
                climb: climb,
                liveActivitySessionID: draft.sessionID,
                recoveredDraft: draft,
                resumeNotice: notice
            )
        },
        makeJustClimbSession: @escaping @MainActor (ActiveHeadphoneWorkoutDraft, HeadphoneSessionResumeNotice?) -> LiveClimbSessionViewModel = { draft, notice in
            ActiveHeadphoneWorkoutRecoveryView.resumedJustClimb(from: draft, resumeNotice: notice)
        },
        makeRoutineSession: @escaping @MainActor (Routine, ActiveHeadphoneWorkoutDraft, HeadphoneSessionResumeNotice?) -> ActiveRoutineViewModel = { routine, draft, notice in
            ActiveRoutineViewModel(routine: routine, recoveredDraft: draft, resumeNotice: notice)
        },
        makeCheckpointer: @escaping @MainActor () -> HeadphoneSessionCheckpointer = { HeadphoneSessionCheckpointer() }
    ) {
        self.draftStore = draftStore
        self.featureFlags = featureFlags
        self.stepEstimator = stepEstimator
        self.systemUptime = systemUptime
        self.crashedLastRun = crashedLastRun
        self.now = now
        self.climbLookup = climbLookup
        self.makeCheckpointer = makeCheckpointer
        self.makeLiveClimbSession = makeLiveClimbSession
        self.makeJustClimbSession = makeJustClimbSession
        self.makeRoutineSession = makeRoutineSession
    }

    /// What should happen to this draft, from the facts a launch can read.
    func assess(_ draft: ActiveHeadphoneWorkoutDraft) -> HeadphoneSessionRecoveryAssessment {
        HeadphoneSessionRecoveryPlanner.assess(
            HeadphoneSessionRecoveryPlanner.Inputs(
                lastCheckpointAt: draft.lastCheckpointAt,
                diagnostics: draft.checkpointDiagnostics,
                now: now(),
                systemUptime: systemUptime(),
                crashedLastRun: crashedLastRun(),
                autoResumeEnabled: RemoteFeatureGate.allows(
                    .headphoneSessionAutoResume,
                    path: "HeadphoneSessionRecoveryCoordinator.assess",
                    store: featureFlags
                ),
                climberEndedSession: draft.status == .stopped
            )
        )
    }

    /// Reports the loss once per draft, however many surfaces find it.
    func reportSessionLost(_ draft: ActiveHeadphoneWorkoutDraft, assessment: HeadphoneSessionRecoveryAssessment) {
        guard !reportedLostDraftIDs.contains(draft.id) else { return }
        reportedLostDraftIDs.insert(draft.id)

        let diagnostics = draft.checkpointDiagnostics
        TelemetryManager.shared.track(
            HeadphoneSessionRecoveryAnalyticsEvent.sessionLost(
                mode: draft.kind,
                draftAgeSeconds: Int(assessment.gap.rounded(.down)),
                steps: draft.steps,
                durationSeconds: Int(draft.durationSeconds.rounded(.down)),
                lastWorkoutSessionState: diagnostics?.workoutSessionState ?? "unknown",
                availableMemoryMB: diagnostics?.availableMemoryBytes.map { Int($0 / 1_048_576) },
                memoryWarningCount: diagnostics?.memoryWarningCount,
                lossReason: assessment.lossReason,
                plan: assessment.plan
            )
        )
        AppDiagnosticsRecorder.shared.record(
            "headphone_session_lost",
            level: .warning,
            details: draft.diagnosticDetails.merging([
                "gap_seconds": String(Int(assessment.gap.rounded(.down))),
                "loss_reason": assessment.lossReason.rawValue,
                "plan": assessment.plan == .autoResume ? "auto_resume" : "prompt"
            ]) { current, _ in current }
        )
    }

    /// A session already running for this draft in this process - started by an earlier surface,
    /// the HealthKit relaunch, or a screen a tab switch took away.
    func runningSession(for draft: ActiveHeadphoneWorkoutDraft) -> HeadphoneSessionResumption.Session? {
        if let live = LiveClimbSessionCoordinator.shared.activeViewModel(sessionID: draft.sessionID) {
            return .liveClimb(live)
        }
        if let routine = ActiveRoutineSessionCoordinator.shared.activeViewModel(sessionID: draft.sessionID) {
            return .routine(routine, routine.routine)
        }
        return nil
    }

    /// Credits the gap since the draft's last checkpoint exactly once, with the machine's number
    /// when the climber typed one. A second credit from the same checkpoint - a Resume retried
    /// after the sensor refused, or a Save after it - measures no gap at all, and neither does a
    /// session the climber already ended: its clock stopped where they stopped it.
    @discardableResult
    func creditGap(
        to draft: ActiveHeadphoneWorkoutDraft,
        correctedSteps: Int?,
        in modelContext: ModelContext,
        at creditedAt: Date
    ) throws -> ActiveHeadphoneWorkoutDraftStore.TrackingGapCredit {
        let alreadyCredited = gapCreditedCheckpoints[draft.id] == draft.lastCheckpointAt
        let effectiveAt = alreadyCredited || draft.status == .stopped ? draft.lastCheckpointAt : creditedAt
        let credit: ActiveHeadphoneWorkoutDraftStore.TrackingGapCredit
        if let correctedSteps {
            credit = try draftStore.applyRecoveryStepSync(
                correctedSteps: correctedSteps,
                to: draft,
                in: modelContext,
                syncedAt: effectiveAt
            )
        } else {
            credit = try draftStore.creditTrackingGap(to: draft, in: modelContext, resumedAt: effectiveAt)
        }
        gapCreditedCheckpoints[draft.id] = draft.lastCheckpointAt
        return credit
    }

    /// Credits the gap, restarts the session for the draft's mode, and keeps it until a screen
    /// adopts it. A draft whose session is already running returns that session untouched.
    /// Throws when the climb or routine is gone or the sensor refuses to start; the caller then
    /// falls back to the recovery screen with the draft untouched beyond the credit.
    @discardableResult
    func resume(
        _ draft: ActiveHeadphoneWorkoutDraft,
        modelContext: ModelContext,
        assessment: HeadphoneSessionRecoveryAssessment,
        correctedSteps: Int? = nil,
        showsNotice: Bool = true
    ) throws -> HeadphoneSessionResumption {
        if let existing = resumptions[draft.id] {
            return existing
        }
        if let running = runningSession(for: draft) {
            return HeadphoneSessionResumption(
                draftID: draft.id,
                sessionID: draft.sessionID,
                session: running,
                assessment: assessment
            )
        }

        guard draft.status != .stopped else {
            throw HeadphoneSessionRecoveryError.sessionEnded
        }

        let routine = draft.kind == .routine ? fetchRoutine(for: draft, in: modelContext) : nil
        let climb = draft.kind == .liveClimb ? draft.climbId.flatMap(climbLookup) : nil
        switch draft.kind {
        case .liveClimb where climb == nil:
            throw HeadphoneSessionRecoveryError.climbUnavailable
        case .routine where routine == nil:
            throw HeadphoneSessionRecoveryError.routineUnavailable
        default:
            break
        }

        let resumedAt = now()
        let gapStart = draft.lastCheckpointAt
        let credit = try creditGap(to: draft, correctedSteps: correctedSteps, in: modelContext, at: resumedAt)
        let notice: HeadphoneSessionResumeNotice? = showsNotice
            ? HeadphoneSessionResumeNotice(
                gap: credit.gapSeconds,
                lossReason: assessment.lossReason,
                detectedSteps: draft.steps
            )
            : nil

        let session: HeadphoneSessionResumption.Session
        switch draft.kind {
        case .liveClimb:
            let viewModel = makeLiveClimbSession(climb!, draft, notice)
            viewModel.start(modelContext: modelContext)
            if case .failed(let message) = viewModel.phase {
                throw HeadphoneSessionRecoveryError.sessionFailedToStart(message)
            }
            session = .liveClimb(viewModel)
        case .justClimb:
            let viewModel = makeJustClimbSession(draft, notice)
            viewModel.start(modelContext: modelContext)
            if case .failed(let message) = viewModel.phase {
                throw HeadphoneSessionRecoveryError.sessionFailedToStart(message)
            }
            session = .liveClimb(viewModel)
        case .routine:
            let viewModel = makeRoutineSession(routine!, draft, notice)
            viewModel.startSession(modelContext: modelContext, skipsCountdown: true)
            if case .failed(let message) = viewModel.phase {
                throw HeadphoneSessionRecoveryError.sessionFailedToStart(message)
            }
            ActiveRoutineSessionCoordinator.shared.setActive(viewModel, sessionID: draft.sessionID)
            session = .routine(viewModel, routine!)
        }

        let resumption = HeadphoneSessionResumption(
            draftID: draft.id,
            sessionID: draft.sessionID,
            session: session,
            assessment: assessment
        )
        resumptions[draft.id] = resumption
        AppDiagnosticsRecorder.shared.record(
            "headphone_session_auto_resumed",
            level: .warning,
            details: draft.diagnosticDetails.merging([
                "gap_seconds": String(Int(credit.gapSeconds.rounded(.down))),
                "gap_credited": String(credit.credited),
                "loss_reason": assessment.lossReason.rawValue
            ]) { current, _ in current }
        )
        if showsNotice {
            attachPhoneEstimate(to: resumption, from: gapStart, to: resumedAt)
        }
        return resumption
    }

    /// The screen that now shows the session takes it over; the coordinator forgets it.
    func adopt(draftID: UUID) -> HeadphoneSessionResumption? {
        resumptions.removeValue(forKey: draftID)
    }

    /// Closes the draft's server heartbeat when the recovery screen saves or discards it, so a
    /// session settled there is never left open or flagged for good.
    func publishSessionEnd(for draft: ActiveHeadphoneWorkoutDraft, outcome: AttemptHeartbeat.Outcome) {
        let checkpointer = makeCheckpointer()
        checkpointer.adopt(draft)
        checkpointer.publishSessionEnd(outcome: outcome)
    }

    private func attachPhoneEstimate(
        to resumption: HeadphoneSessionResumption,
        from start: Date,
        to end: Date
    ) {
        let estimator = stepEstimator
        Task { @MainActor in
            guard let steps = await estimator.steps(from: start, to: end), steps > 0 else { return }
            switch resumption.session {
            case .liveClimb(let viewModel):
                viewModel.attachPhoneStepEstimate(steps)
            case .routine(let viewModel, _):
                viewModel.attachPhoneStepEstimate(steps)
            }
            AppDiagnosticsRecorder.shared.record(
                "headphone_session_phone_step_estimate",
                details: ["session_id": resumption.sessionID, "steps": String(steps)]
            )
        }
    }

    private func fetchRoutine(for draft: ActiveHeadphoneWorkoutDraft, in modelContext: ModelContext) -> Routine? {
        guard let routineId = draft.routineId else { return nil }
        let descriptor = FetchDescriptor<Routine>(predicate: #Predicate { $0.id == routineId })
        return try? modelContext.fetch(descriptor).first
    }
}
