import Foundation
import Observation
import SwiftData
import UIKit

enum LiveClimbSessionPhase: Equatable {
    case idle
    case recording
    case saving
    case saved(ClimbAttemptStatus)
    case failed(String)
}

enum LiveClimbSessionError: LocalizedError {
    case noStepsRecorded

    var errorDescription: String? {
        switch self {
        case .noStepsRecorded:
            return "No steps were recorded for this attempt."
        }
    }
}

struct LiveStepSyncPrompt: Identifiable, Equatable {
    let id = UUID()
    let detectedSteps: Int
    let gapDuration: TimeInterval
    let interruptionCount: Int
}

struct LiveStepSyncConfirmation: Identifiable, Equatable {
    let id = UUID()
    let correctedSteps: Int
}

enum LiveClimbSessionMode: Equatable {
    case liveClimb(Climb)
    case justClimb(JustClimbGoal)

    var climb: Climb? {
        switch self {
        case .liveClimb(let climb):
            return climb
        case .justClimb:
            return nil
        }
    }

    var justClimbGoal: JustClimbGoal? {
        switch self {
        case .liveClimb:
            return nil
        case .justClimb(let goal):
            return goal
        }
    }

    var draftKind: ActiveHeadphoneWorkoutDraftKind {
        switch self {
        case .liveClimb:
            return .liveClimb
        case .justClimb:
            return .justClimb
        }
    }

    var title: String {
        switch self {
        case .liveClimb(let climb):
            return climb.name
        case .justClimb(let goal):
            return goal.title
        }
    }

    var subtitle: String {
        switch self {
        case .liveClimb(let climb):
            return climb.displayLocation
        case .justClimb(let goal):
            return goal.subtitle
        }
    }

    var targetStepCount: Int? {
        switch self {
        case .liveClimb(let climb):
            return climb.referenceStepCount
        case .justClimb(let goal):
            return goal.targetStepCount
        }
    }

    var targetDuration: TimeInterval? {
        switch self {
        case .liveClimb:
            return nil
        case .justClimb(let goal):
            return goal.targetDuration
        }
    }

    var motionTargetStepCount: Int? {
        targetStepCount
    }

    var workoutName: String {
        switch self {
        case .liveClimb(let climb):
            return "\(climb.name) Live Climb"
        case .justClimb:
            return "Just Climb"
        }
    }

    var trackingMode: HeadphoneMotionWorkoutTrackingMode {
        switch self {
        case .liveClimb:
            return .liveClimb
        case .justClimb:
            return .justClimb
        }
    }

    func replayContext(progressScaleSteps: Int) -> LiveReplayLeaderboardContext {
        let targetSteps = max(targetStepCount ?? progressScaleSteps, 1)

        switch self {
        case .liveClimb(let climb):
            return .liveClimb(
                climbId: climb.id,
                targetSteps: targetSteps
            )
        case .justClimb:
            return .justClimbGlobal(targetSteps: targetSteps)
        }
    }

    var liveActivityClimbID: String {
        switch self {
        case .liveClimb(let climb):
            return climb.id
        case .justClimb:
            return "just-climb"
        }
    }

    var isLandmarkClimb: Bool {
        switch self {
        case .liveClimb:
            return true
        case .justClimb:
            return false
        }
    }
}

@MainActor
@Observable
final class LiveClimbSessionViewModel {
    let mode: LiveClimbSessionMode
    let motionSession: any HeadphoneMotionSessionServicing
    let analyticsEntryPoint: LiveClimbAnalyticsEvent.EntryPoint
    let liveActivitySessionID: String

    private let climbService: ClimbService
    private let settingsManager: SettingsManager
    private let leaderboardService: LiveReplayLeaderboardServicing
    private let liveActivityManager: LiveClimbActivityManager
    private let backgroundSessionService: LiveClimbBackgroundSessionService
    private let draftStore: ActiveHeadphoneWorkoutDraftStore
    private let heartRateRecorder: LiveHeartRateRecorder
    private let now: () -> Date
    /// Read once per session. `leaderboardRows` is rebuilt on every step and
    /// elapsed tick, so the climber's name cannot be resolved from the cache
    /// inside it.
    private let currentUserDisplayName = UserDataRepository.shared.getCachedDisplayName()

    private(set) var phase: LiveClimbSessionPhase = .idle
    private(set) var recordedResult: HeadphoneMotionSessionResult?
    private(set) var savedWorkout: Workout?
    private(set) var leaderboardSummary: LiveReplayLeaderboardSummary = .empty
    private(set) var leaderboardWindow: LiveReplayLeaderboardWindow?
    private(set) var leaderboardFetchFailed = false
    private(set) var stepSyncPrompt: LiveStepSyncPrompt?
    private(set) var stepSyncConfirmation: LiveStepSyncConfirmation?

    let heartRateMonitor: HeartRateMonitorService
    private(set) var heartRateZoneProfile = HeartRateZoneProfile(age: nil)

    private var hasSavedSession = false
    private var stepTimelineRecorder: LiveClimbStepTimelineRecorder
    private var isLeaderboardRefreshInFlight = false
    /// Whether the server has answered with a summary at all, which is not the same
    /// question as whether its count is zero: a climb nobody has finished answers
    /// zero forever, and re-asking it every tick would be a per-second read.
    private var hasFetchedLeaderboardSummary = false
    /// When the unanswered summary may be asked for again. An absolute date rather
    /// than a counter, so a flaky connection is paced by the clock instead of by how
    /// often the session happens to tick, and stamped when an attempt resolves rather
    /// than when it started - a read that hangs longer than the interval would
    /// otherwise leave the next tick already eligible.
    private var nextLeaderboardSummaryAttemptAt: Date?
    private let leaderboardSummaryRetryInterval: TimeInterval = 5
    /// The count's own lane. It is not awaited by the refresh that starts it and it
    /// holds no part of the window path's in-flight slot, so a summary read that
    /// stalls cannot delay, skip or starve a single refresh of the race rows. Doubles
    /// as the single-in-flight guard: a non-nil task is an attempt already running.
    @ObservationIgnored private(set) var leaderboardSummaryFetchTask: Task<Void, Never>?
    private var lastExhaustedLeaderboardWindowRefreshAt: Date?
    private var lastPeriodicLeaderboardWindowRefreshAt: Date?
    private var promptedStepSyncInterruptionCounts: Set<Int> = []
    private var skippedStepSyncInterruptionCounts: Set<Int> = []
    private let stepSyncPromptMinimumGapDuration: TimeInterval = 20
    private var activeDraft: ActiveHeadphoneWorkoutDraft?
    private var lastDraftCheckpointAt: Date?
    private let draftCheckpointInterval: TimeInterval = 2
    /// The heart-rate payload is the largest thing a checkpoint writes, so it
    /// rides a slower cadence than the rest of the draft. Lifecycle and finish
    /// checkpoints force it, bounding what an interruption can lose.
    private var lastHeartRateCheckpointAt: Date?
    private let heartRateCheckpointInterval: TimeInterval = 15

    init(
        climb: Climb,
        analyticsEntryPoint: LiveClimbAnalyticsEvent.EntryPoint = .unknown,
        motionSession: any HeadphoneMotionSessionServicing = HeadphoneMotionSessionService(),
        climbService: ClimbService = .shared,
        settingsManager: SettingsManager = .shared,
        leaderboardService: LiveReplayLeaderboardServicing = LiveReplayLeaderboardService.shared,
        liveActivityManager: LiveClimbActivityManager = .shared,
        backgroundSessionService: LiveClimbBackgroundSessionService = .shared,
        draftStore: ActiveHeadphoneWorkoutDraftStore = ActiveHeadphoneWorkoutDraftStore(),
        heartRateRecorder: LiveHeartRateRecorder = LiveHeartRateRecorder(),
        heartRateMonitor: HeartRateMonitorService = .shared,
        liveActivitySessionID: String = UUID().uuidString,
        recoveredDraft: ActiveHeadphoneWorkoutDraft? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.mode = .liveClimb(climb)
        self.analyticsEntryPoint = analyticsEntryPoint
        self.liveActivitySessionID = liveActivitySessionID
        self.motionSession = motionSession
        self.climbService = climbService
        self.settingsManager = settingsManager
        self.leaderboardService = leaderboardService
        self.liveActivityManager = liveActivityManager
        self.backgroundSessionService = backgroundSessionService
        self.draftStore = draftStore
        self.heartRateRecorder = heartRateRecorder
        self.heartRateMonitor = heartRateMonitor
        self.activeDraft = recoveredDraft
        self.now = now
        heartRateRecorder.restore(samples: recoveredDraft?.heartRateSamples ?? [])
        self.stepTimelineRecorder = LiveClimbStepTimelineRecorder(intervalSeconds: 10)
        self.motionSession.setStepSampleHandler { [weak self] sample in
            self?.recordLiveStepSample(sample)
        }
    }

    init(
        justClimbGoal: JustClimbGoal,
        analyticsEntryPoint: LiveClimbAnalyticsEvent.EntryPoint = .unknown,
        motionSession: any HeadphoneMotionSessionServicing = HeadphoneMotionSessionService(),
        climbService: ClimbService = .shared,
        settingsManager: SettingsManager = .shared,
        leaderboardService: LiveReplayLeaderboardServicing = LiveReplayLeaderboardService.shared,
        liveActivityManager: LiveClimbActivityManager = .shared,
        backgroundSessionService: LiveClimbBackgroundSessionService = .shared,
        draftStore: ActiveHeadphoneWorkoutDraftStore = ActiveHeadphoneWorkoutDraftStore(),
        heartRateRecorder: LiveHeartRateRecorder = LiveHeartRateRecorder(),
        heartRateMonitor: HeartRateMonitorService = .shared,
        liveActivitySessionID: String = UUID().uuidString,
        recoveredDraft: ActiveHeadphoneWorkoutDraft? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.mode = .justClimb(justClimbGoal)
        self.analyticsEntryPoint = analyticsEntryPoint
        self.liveActivitySessionID = liveActivitySessionID
        self.motionSession = motionSession
        self.climbService = climbService
        self.settingsManager = settingsManager
        self.leaderboardService = leaderboardService
        self.liveActivityManager = liveActivityManager
        self.backgroundSessionService = backgroundSessionService
        self.draftStore = draftStore
        self.heartRateRecorder = heartRateRecorder
        self.heartRateMonitor = heartRateMonitor
        self.activeDraft = recoveredDraft
        self.now = now
        heartRateRecorder.restore(samples: recoveredDraft?.heartRateSamples ?? [])
        self.stepTimelineRecorder = LiveClimbStepTimelineRecorder(intervalSeconds: 10)
        self.motionSession.setStepSampleHandler { [weak self] sample in
            self?.recordLiveStepSample(sample)
        }
    }

    var totalRecordedSteps: Int {
        let steps = max(motionSession.stepCount, 0)
        guard let targetStepCount = mode.targetStepCount else {
            return steps
        }

        return min(targetStepCount, steps)
    }

    var targetRemainingSteps: Int? {
        mode.motionTargetStepCount
    }

    var totalProgressFraction: Double {
        if let targetStepCount = mode.targetStepCount, targetStepCount > 0 {
            return min(max(Double(totalRecordedSteps) / Double(targetStepCount), 0), 1)
        }

        if let targetDuration = mode.targetDuration, targetDuration > 0 {
            return min(max(displayedDuration / targetDuration, 0), 1)
        }

        return 0
    }

    var totalProgressPercent: Int {
        Int((totalProgressFraction * 100).rounded())
    }

    var displayedDuration: TimeInterval {
        motionSession.duration
    }

    var displayedFloors: Int {
        Workout.stepsToFloors(totalRecordedSteps)
    }

    var estimatedDuration: TimeInterval {
        if let targetDuration = mode.targetDuration {
            return targetDuration
        }

        guard let targetStepCount = mode.targetStepCount else {
            return 0
        }

        let spm = max(settingsManager.effectiveBaseLevelSPM, 1)
        return (Double(targetStepCount) / Double(spm)) * 60
    }

    var currentStepsPerMinute: Int {
        guard displayedDuration > 0 else { return 0 }
        return Int((Double(totalRecordedSteps) / (displayedDuration / 60)).rounded())
    }

    var elapsedClock: String {
        let totalSeconds = max(Int(displayedDuration.rounded(.down)), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(minutes < 10 ? "0" : "")\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
        }

        return "\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
    }

    var replayContext: LiveReplayLeaderboardContext {
        mode.replayContext(progressScaleSteps: leaderboardProgressScale)
    }

    var leaderboardRows: [LiveReplayLeaderboardRow] {
        guard let leaderboardWindow else {
            return [
                LiveReplayLeaderboardRow.currentUser(
                    rank: nil,
                    steps: totalRecordedSteps,
                    displayName: currentUserDisplayName
                )
            ]
        }

        return leaderboardWindow.locallyRankedRows(
            currentSteps: totalRecordedSteps,
            currentElapsedSeconds: Int(displayedDuration.rounded(.down)),
            displayName: currentUserDisplayName
        )
    }

    var leaderboardProgressScale: Int {
        max(
            mode.targetStepCount ?? JustClimbGoal.defaultOpenStepScale,
            totalRecordedSteps,
            1
        )
    }

    var leaderboardCurrentProgressFraction: Double {
        let scale = max(leaderboardProgressScale, 1)
        return min(max(Double(totalRecordedSteps) / Double(scale), 0), 1)
    }

    /// Where this climber's previous best on this climb had reached at this
    /// moment, in steps, or nil when they have never finished it.
    ///
    /// The board withdrew that completion from the standings, so this is all that
    /// is left of it: a position for the `BEST` marker. It is never ranked, never
    /// counted in the field size, and never accompanied by a number.
    var previousBestStepsAtBucket: Int? {
        leaderboardWindow?.previousBestStepsAtBucket(
            currentElapsedSeconds: Int(displayedDuration.rounded(.down))
        )
    }

    /// The same position as a fraction of the summit, for the Just Me rail.
    var previousBestProgressFraction: Double? {
        guard let previousBestStepsAtBucket,
              previousBestStepsAtBucket > 0,
              let targetSteps = mode.targetStepCount,
              targetSteps > 0 else {
            return nil
        }

        return min(Double(previousBestStepsAtBucket) / Double(targetSteps), 1)
    }

    var leaderboardTotalClimbers: Int {
        max(leaderboardWindow?.totalClimbers ?? 0, leaderboardSummary.totalClimbers)
    }

    var leaderboardCompletedCount: Int {
        leaderboardSummary.completedCount
    }

    /// The field this session's board ranks, for the panel's field-size line, or
    /// nil when nothing on hand measures it.
    ///
    /// Only the server's own finisher count qualifies. The fetched window's total
    /// is a display floor that already counts this climber a second time, and
    /// `leaderboardRows` synthesizes a lone current-user row before the first
    /// fetch - either would have the panel assert a field it does not have. An
    /// open Just Climb races completions, a population no count here measures, so
    /// it names none.
    var leaderboardField: LiveReplayFieldSize? {
        let contextType = replayContext.type
        guard contextType.collapsesRepeatFinishers,
              leaderboardSummary.totalClimbers > 0 else { return nil }

        return LiveReplayFieldSize(
            population: contextType.fieldPopulation,
            count: leaderboardSummary.totalClimbers
        )
    }

    var leaderboardUpdatedElapsedSeconds: Int? {
        leaderboardWindow?.bucketElapsedSeconds
    }

    var currentLeaderboardRank: Int? {
        leaderboardRows.first(where: \.isLiveAttempt)?.rank ?? leaderboardWindow?.currentUserRank
    }

    var currentRankDisplay: String {
        currentLeaderboardRank.map { "#\($0)" } ?? "—"
    }

    var completionLeaderboardRank: Int? {
        leaderboardWindow?.currentUserRank ?? leaderboardRows.first(where: \.isLiveAttempt)?.rank
    }

    var completionLeaderboardTotal: Int? {
        let total = max(leaderboardWindow?.totalClimbers ?? 0, leaderboardSummary.completedCount)
        return total > 0 ? total : nil
    }

    var isRecording: Bool {
        phase == .recording
    }

    var isActivelyRecording: Bool {
        phase == .recording && motionSession.status.isRecording
    }

    var shouldShowRankedCompletionSummary: Bool {
        guard case .saved(.completed) = phase else { return false }
        return true
    }

    var durationGoalReached: Bool {
        guard let targetDuration = mode.targetDuration,
              targetDuration > 0 else {
            return false
        }

        return displayedDuration >= targetDuration
    }

    var shouldShowTrackingRecoveryStatus: Bool {
        phase == .recording && motionSession.trackingIntegrity.shouldShowRecoveryStatus
    }

    var isBusy: Bool {
        phase == .saving
    }

    var discardMessage: String {
        mode.isLandmarkClimb
            ? "This will stop tracking and discard this climb attempt."
            : "This will stop tracking and discard this Just Climb session."
    }

    func start(modelContext: ModelContext) {
        guard phase == .idle else { return }

        let preexistingDraft = activeDraft
        AppDiagnosticsRecorder.shared.record(
            "headphone_session_start_requested",
            details: [
                "kind": mode.draftKind.rawValue,
                "session_id": liveActivitySessionID,
                "resumed_from_draft": preexistingDraft == nil ? "false" : "true"
            ]
        )
        // Strap-on-and-go: reconnect the remembered heart-rate monitor
        // silently, and resolve the climber's zone bands from their profile
        // age. Both are best-effort — the session never waits on them.
        heartRateRecorder.prepareForSession(
            restoring: preexistingDraft?.heartRateSamples ?? []
        )
        Task { [weak self] in
            let profile = await HeartRateZoneProfileResolver.resolve()
            self?.heartRateZoneProfile = profile
        }

        do {
            stepTimelineRecorder.reset()
            if let splitCurve = activeDraft?.splitCurve {
                stepTimelineRecorder.restore(curve: splitCurve)
            }
            stepSyncPrompt = nil
            stepSyncConfirmation = nil
            promptedStepSyncInterruptionCounts.removeAll(keepingCapacity: true)
            skippedStepSyncInterruptionCounts.removeAll(keepingCapacity: true)
            if activeDraft == nil {
                stepTimelineRecorder.record(
                    elapsedSeconds: 0,
                    cumulativeSteps: 0,
                    source: .headphoneMotion
                )
            }

            let draft = try prepareDraftIfNeeded(modelContext: modelContext)
            try motionSession.startRecording(
                targetStepCount: targetRemainingSteps,
                resumeState: draft?.resumeState
            )
            backgroundSessionService.start(at: draft?.startedAt ?? Date())
            phase = .recording
            AppDiagnosticsRecorder.shared.record(
                "headphone_session_recording_started",
                details: draft?.diagnosticDetails ?? [
                    "kind": mode.draftKind.rawValue,
                    "session_id": liveActivitySessionID
                ]
            )
            switch mode {
            case .liveClimb(let climb):
                TelemetryManager.shared.track(
                    LiveClimbAnalyticsEvent.attemptStarted(
                        climb: climb,
                        entryPoint: analyticsEntryPoint
                    )
                )
            case .justClimb(let goal):
                TelemetryManager.shared.track(
                    WorkoutSessionAnalyticsEvent.justClimbStarted(
                        context: JustClimbAnalyticsContext(
                            goal: goal,
                            entryPoint: analyticsEntryPoint
                        )
                    )
                )
            }
            recordLiveSplitSample()
            checkpointDraft(modelContext: modelContext, force: true)
            LiveClimbSessionCoordinator.shared.setActive(self)
            Task { [weak self] in
                await self?.beginLiveActivity()
            }
        } catch {
            if preexistingDraft == nil,
               let activeDraft,
               activeDraft.status == .recording,
               activeDraft.steps == 0 {
                ActiveHeadphoneWorkoutRuntimeRegistry.shared.markInactive(activeDraft)
                try? draftStore.delete(activeDraft, in: modelContext)
                self.activeDraft = nil
            }
            phase = .failed(error.localizedDescription)
            AppDiagnosticsRecorder.shared.record(
                "headphone_session_start_failed",
                level: .error,
                details: [
                    "kind": mode.draftKind.rawValue,
                    "session_id": liveActivitySessionID,
                    "error": error.localizedDescription
                ]
            )
        }
    }

    func finishAndSave(
        modelContext: ModelContext,
        reason: HeadphoneMotionSessionStopReason
    ) async {
        guard !hasSavedSession,
              phase == .recording || motionSession.status.isRecording else {
            return
        }

        phase = .saving
        stepSyncPrompt = nil
        AppDiagnosticsRecorder.shared.record(
            "headphone_session_finish_requested",
            details: [
                "kind": mode.draftKind.rawValue,
                "session_id": liveActivitySessionID,
                "reason": reason.rawValue
            ]
        )
        await updateLiveActivity(status: .saving, force: true)
        defer {
            backgroundSessionService.stop()
        }

        do {
            let result = try await motionSession.stopRecording(reason: reason)
            guard result.hasRecordedSteps else {
                throw LiveClimbSessionError.noStepsRecorded
            }

            let finalSplitCurve = stepTimelineRecorder.record(
                elapsedSeconds: Int(result.duration.rounded(.down)),
                cumulativeSteps: result.steps,
                source: .headphoneMotion
            )
            checkpointDraft(
                modelContext: modelContext,
                splitCurve: finalSplitCurve,
                result: result,
                status: .stopped,
                force: true
            )
            let savedSession = try saveWorkout(
                from: result,
                splitCurve: finalSplitCurve,
                modelContext: modelContext
            )
            savedWorkout = savedSession.workout
            recordedResult = result
            hasSavedSession = true

            let savedStatus = savedSession.attemptStatus
            trackSavedAttempt(result: result, status: savedStatus)
            phase = .saved(savedStatus)
            clearDraft(modelContext: modelContext)
            AppDiagnosticsRecorder.shared.record(
                "headphone_session_saved",
                details: [
                    "kind": mode.draftKind.rawValue,
                    "session_id": liveActivitySessionID,
                    "steps": String(result.steps),
                    "duration_seconds": String(Int(result.duration.rounded(.down))),
                    "status": savedStatus.rawValue
                ]
            )
            await liveActivityManager.end(status: .finished)
            LiveClimbSessionCoordinator.shared.clearIfActive(sessionID: liveActivitySessionID)
        } catch {
            phase = .failed(error.localizedDescription)
            AppDiagnosticsRecorder.shared.record(
                "headphone_session_save_failed",
                level: .error,
                details: [
                    "kind": mode.draftKind.rawValue,
                    "session_id": liveActivitySessionID,
                    "error": error.localizedDescription
                ]
            )
            await liveActivityManager.end(status: .failed)
            LiveClimbSessionCoordinator.shared.clearIfActive(sessionID: liveActivitySessionID)
        }
    }

    func discard(modelContext: ModelContext) async {
        switch mode {
        case .liveClimb(let climb):
            TelemetryManager.shared.track(
                LiveClimbAnalyticsEvent.attemptDiscarded(
                    climb: climb,
                    entryPoint: analyticsEntryPoint,
                    progressFraction: totalProgressFraction
                )
            )
        case .justClimb(let goal):
            TelemetryManager.shared.track(
                WorkoutSessionAnalyticsEvent.justClimbDiscarded(
                    context: JustClimbAnalyticsContext(
                        goal: goal,
                        entryPoint: analyticsEntryPoint
                    ),
                    durationSeconds: Int(displayedDuration.rounded(.down)),
                    steps: totalRecordedSteps,
                    progressFraction: totalProgressFraction
                )
            )
        }

        if motionSession.status.isRecording {
            _ = try? await motionSession.stopRecording(reason: .discarded)
        }
        AppDiagnosticsRecorder.shared.record(
            "headphone_session_discarded",
            details: [
                "kind": mode.draftKind.rawValue,
                "session_id": liveActivitySessionID,
                "steps": String(totalRecordedSteps),
                "duration_seconds": String(Int(displayedDuration.rounded(.down)))
            ]
        )
        backgroundSessionService.stop()
        clearDraft(modelContext: modelContext)

        await liveActivityManager.end(status: .ended)
        LiveClimbSessionCoordinator.shared.clearIfActive(sessionID: liveActivitySessionID)
    }

    func evaluateStepSyncPrompt() {
        guard phase == .recording,
              stepSyncPrompt == nil,
              motionSession.sampleCount > 0 else {
            return
        }

        guard !motionSession.trackingIntegrity.isCurrentlyUnavailable,
              let resolvedGap = motionSession.lastResolvedTrackingGap,
              resolvedGap.duration >= stepSyncPromptMinimumGapDuration,
              resolvedGap.interruptionCount > 0,
              !promptedStepSyncInterruptionCounts.contains(resolvedGap.interruptionCount),
              !skippedStepSyncInterruptionCounts.contains(resolvedGap.interruptionCount) else {
            return
        }

        promptedStepSyncInterruptionCounts.insert(resolvedGap.interruptionCount)
        stepSyncPrompt = LiveStepSyncPrompt(
            detectedSteps: motionSession.stepCount,
            gapDuration: resolvedGap.duration,
            interruptionCount: resolvedGap.interruptionCount
        )
    }

    func syncCurrentMachineSteps(_ correctedSteps: Int) {
        guard let prompt = stepSyncPrompt else { return }

        guard let correction = motionSession.applyStepCorrection(
            correctedSteps: correctedSteps,
            trackingGapDuration: prompt.gapDuration
        ) else {
            stepSyncPrompt = nil
            return
        }

        _ = stepTimelineRecorder.recordCorrection(correction)
        stepSyncPrompt = nil
        stepSyncConfirmation = LiveStepSyncConfirmation(correctedSteps: correction.correctedSteps)

        Task { [weak self] in
            await self?.refreshReplayLeaderboardIfNeeded(force: true)
            await self?.updateLiveActivity(force: true)
        }
    }

    func skipStepSyncPrompt() {
        if let prompt = stepSyncPrompt {
            skippedStepSyncInterruptionCounts.insert(prompt.interruptionCount)
        }
        stepSyncPrompt = nil
    }

    func dismissStepSyncConfirmation() {
        stepSyncConfirmation = nil
    }

    func recordLiveSplitSample(modelContext: ModelContext? = nil) {
        guard phase == .recording,
              motionSession.status.isRecording else { return }

        _ = stepTimelineRecorder.record(
            elapsedSeconds: Int(motionSession.duration.rounded(.down)),
            cumulativeSteps: motionSession.stepCount,
            source: .headphoneMotion
        )
        recordHeartRateSampleForSessionTick()
        if let modelContext {
            checkpointDraft(modelContext: modelContext)
        }
    }

    // MARK: - Heart rate

    var liveHeartRateStatus: LiveHeartRateStatus? {
        guard phase == .recording else { return nil }
        return LiveHeartRateStatus.resolve(
            hasRememberedDevice: heartRateMonitor.rememberedDevice != nil,
            connectionState: heartRateMonitor.connectionState,
            freshMeasurement: heartRateRecorder.currentMeasurement,
            zoneProfile: heartRateZoneProfile
        )
    }

    var heartRateSamplesSnapshot: [HeartRateDataPoint] {
        heartRateRecorder.samples
    }

    /// Buffers one reading per second-tick while recording so completed
    /// workouts carry the same heart-rate series shape enrichment writes -
    /// the existing sync pipeline uploads it with zero extra plumbing.
    func recordHeartRateSampleForSessionTick(at now: Date = Date()) {
        guard let measurement = heartRateRecorder.currentMeasurement else { return }
        recordHeartRateSample(measurement, capturedAt: now)
    }

    /// Places the reading on the logical workout timeline - the draft's start
    /// plus the resume-inclusive elapsed clock - so a resumed session extends
    /// one continuous series. Without a draft there is no timeline to anchor
    /// to, so the reading falls back to wall clock rather than being projected
    /// to a timestamp minutes in the future.
    func recordHeartRateSample(_ measurement: HeartRateMeasurement, capturedAt: Date = Date()) {
        heartRateRecorder.record(
            measurement,
            capturedAt: capturedAt,
            sessionStartedAt: activeDraft?.startedAt,
            sessionElapsed: displayedDuration
        )
    }

    var heartRateWorkoutSummary: LiveHeartRateWorkoutSummary {
        heartRateRecorder.workoutSummary
    }

    func checkpointForLifecycleChange(modelContext: ModelContext) {
        guard phase == .recording,
              motionSession.status.isRecording else { return }

        let curve = stepTimelineRecorder.record(
            elapsedSeconds: Int(motionSession.duration.rounded(.down)),
            cumulativeSteps: motionSession.stepCount,
            source: .headphoneMotion
        )
        recordHeartRateSampleForSessionTick()
        checkpointDraft(
            modelContext: modelContext,
            splitCurve: curve,
            force: true
        )
        AppDiagnosticsRecorder.shared.record(
            "headphone_session_lifecycle_checkpoint",
            details: [
                "kind": mode.draftKind.rawValue,
                "session_id": liveActivitySessionID,
                "steps": String(totalRecordedSteps),
                "duration_seconds": String(Int(displayedDuration.rounded(.down)))
            ]
        )
    }

    private func recordLiveStepSample(_ sample: LiveClimbStepSample) {
        guard phase == .recording,
              motionSession.status.isRecording else { return }

        _ = stepTimelineRecorder.record(sample)
        Task { [weak self] in
            await self?.updateLiveActivity()
        }
    }

    func refreshReplayLeaderboardIfNeeded(force: Bool = false) async {
        guard phase == .recording else { return }

        let requestedAt = now()

        startLeaderboardSummaryFetchIfNeeded(force: force, now: requestedAt)

        guard !isLeaderboardRefreshInFlight else { return }

        let forceFreshWindow = force ||
            shouldForceFreshLeaderboardWindowRefresh(now: requestedAt) ||
            shouldForcePeriodicLeaderboardWindowRefresh(now: requestedAt)

        isLeaderboardRefreshInFlight = true
        defer { isLeaderboardRefreshInFlight = false }

        recordLiveSplitSample()

        do {
#if DEBUG
            let refreshStartedAt = Date()
#endif
            if let window = try await leaderboardService.refreshIfNeeded(
                context: replayContext,
                elapsedSeconds: Int(displayedDuration.rounded(.down)),
                currentSteps: totalRecordedSteps,
                force: forceFreshWindow
            ) {
                leaderboardWindow = window
#if DEBUG
                let duration = Date().timeIntervalSince(refreshStartedAt)
                debugLog(
                    "Live replay leaderboard fetched \(replayContext.contextKey) " +
                    "bucket=\(window.bucketIndex) rank=\(window.currentUserRank ?? -1) " +
                    "rows=\(window.rows.count) force=\(forceFreshWindow) " +
                    "steps=\(totalRecordedSteps) duration=\(String(format: "%.2f", duration))s"
                )
#endif
            } else {
#if DEBUG
                debugLog(
                    "Live replay leaderboard skipped \(replayContext.contextKey) " +
                    "force=\(forceFreshWindow) steps=\(totalRecordedSteps)"
                )
#endif
            }

            leaderboardFetchFailed = false
        } catch {
#if DEBUG
            debugLog("Live replay leaderboard fetch failed for \(replayContext.contextKey): \(error.localizedDescription)")
#endif
            leaderboardFetchFailed = true
        }

        await updateLiveActivity(force: force || forceFreshWindow)
    }

    func updateLiveActivity(force: Bool = false) async {
        await updateLiveActivity(status: nil, force: force)
    }

    private func prepareDraftIfNeeded(modelContext: ModelContext) throws -> ActiveHeadphoneWorkoutDraft? {
        if let activeDraft {
            draftStore.setActiveDraftID(activeDraft.id)
            ActiveHeadphoneWorkoutRuntimeRegistry.shared.markActive(activeDraft)
            return activeDraft
        }

        let draft = ActiveHeadphoneWorkoutDraft(
            sessionID: liveActivitySessionID,
            kind: mode.draftKind,
            title: mode.title,
            subtitle: mode.subtitle,
            workoutName: mode.workoutName,
            targetStepCount: mode.targetStepCount,
            targetDurationSeconds: mode.targetDuration,
            climbId: mode.climb?.id,
            justClimbGoalKind: mode.justClimbGoal?.kind,
            justClimbDurationMinutes: mode.justClimbGoal?.durationMinutes,
            justClimbStepCount: mode.justClimbGoal?.stepCount
        )
        try draftStore.insert(draft, in: modelContext)
        activeDraft = draft
        ActiveHeadphoneWorkoutRuntimeRegistry.shared.markActive(draft)
        return draft
    }

    private func checkpointDraft(
        modelContext: ModelContext,
        splitCurve: LiveReplaySplitCurve? = nil,
        result: HeadphoneMotionSessionResult? = nil,
        status: ActiveHeadphoneWorkoutDraftStatus = .recording,
        force: Bool = false
    ) {
        guard let activeDraft else { return }

        let now = Date()
        if !force,
           let lastDraftCheckpointAt,
           now.timeIntervalSince(lastDraftCheckpointAt) < draftCheckpointInterval {
            return
        }

        let heartRateBuffer = shouldCheckpointHeartRate(draft: activeDraft, now: now, force: force)
            ? heartRateRecorder.sampleBuffer
            : nil
        activeDraft.applyCheckpoint(
            steps: result?.steps ?? totalRecordedSteps,
            durationSeconds: result?.duration ?? displayedDuration,
            sampleCount: result?.sampleCount ?? motionSession.sampleCount,
            splitCurve: splitCurve ?? stepTimelineRecorder.curve,
            trackingIntegrity: result?.trackingIntegrity ?? motionSession.trackingIntegrity,
            stepCorrections: result?.stepCorrections ?? motionSession.stepCorrectionsSnapshot,
            heartRateBuffer: heartRateBuffer,
            status: status,
            checkpointedAt: now
        )
        do {
            try modelContext.save()
            lastDraftCheckpointAt = now
            if heartRateBuffer != nil {
                lastHeartRateCheckpointAt = now
            }
        } catch {
#if DEBUG
            debugLog("Active headphone draft checkpoint failed: \(error.localizedDescription)")
#endif
        }
    }

    private func shouldCheckpointHeartRate(
        draft: ActiveHeadphoneWorkoutDraft,
        now: Date,
        force: Bool
    ) -> Bool {
        guard heartRateRecorder.samples.count != (draft.heartRateSampleCount ?? 0) else {
            return false
        }
        if force {
            return true
        }
        guard let lastHeartRateCheckpointAt else { return true }

        return now.timeIntervalSince(lastHeartRateCheckpointAt) >= heartRateCheckpointInterval
    }

    private func clearDraft(modelContext: ModelContext) {
        guard let activeDraft else {
            draftStore.clearActiveDraftID()
            return
        }

        ActiveHeadphoneWorkoutRuntimeRegistry.shared.markInactive(activeDraft)
        do {
            try draftStore.delete(activeDraft, in: modelContext)
        } catch {
#if DEBUG
            debugLog("Active headphone draft cleanup failed: \(error.localizedDescription)")
#endif
            draftStore.clearActiveDraftID(activeDraft.id)
        }
        self.activeDraft = nil
        lastDraftCheckpointAt = nil
    }

    /// Starts the read behind the field-size count, and never waits on it.
    ///
    /// The race rows are what a climber is here for and the count is garnish, so the
    /// count runs in its own task, off the window path's in-flight slot, with its own
    /// error handling: no latency and no failure of this read can reach
    /// `leaderboardWindow`, `leaderboardRows` or `leaderboardFetchFailed`. A blip on
    /// the session's one forced fetch used to silence the line for the whole race, so
    /// an unanswered count keeps asking - paced by the clock, and only until the
    /// server answers once.
    private func startLeaderboardSummaryFetchIfNeeded(force: Bool, now: Date) {
        guard leaderboardSummaryFetchTask == nil,
              force || shouldRetryLeaderboardSummary(now: now) else {
            return
        }

        leaderboardSummaryFetchTask = Task { [weak self] in
            await self?.fetchLeaderboardSummary()
        }
    }

    private func fetchLeaderboardSummary() async {
        defer { leaderboardSummaryFetchTask = nil }

        do {
            leaderboardSummary = try await leaderboardService.fetchSummary(context: replayContext)
            hasFetchedLeaderboardSummary = true
            nextLeaderboardSummaryAttemptAt = nil
        } catch {
#if DEBUG
            debugLog(
                "Live replay leaderboard summary unavailable for \(replayContext.contextKey): " +
                "\(error.localizedDescription)"
            )
#endif
            nextLeaderboardSummaryAttemptAt = now().addingTimeInterval(leaderboardSummaryRetryInterval)
        }
    }

    private func shouldRetryLeaderboardSummary(now: Date) -> Bool {
        guard !hasFetchedLeaderboardSummary else { return false }
        guard let nextLeaderboardSummaryAttemptAt else { return true }

        return now >= nextLeaderboardSummaryAttemptAt
    }

    private func shouldForceFreshLeaderboardWindowRefresh(now: Date) -> Bool {
        guard let leaderboardWindow,
              leaderboardWindow.needsFreshWindow(
                currentSteps: totalRecordedSteps,
                currentElapsedSeconds: Int(displayedDuration.rounded(.down))
              ) else {
            return false
        }

        if let lastExhaustedLeaderboardWindowRefreshAt,
           now.timeIntervalSince(lastExhaustedLeaderboardWindowRefreshAt) < 2 {
            return false
        }

        lastExhaustedLeaderboardWindowRefreshAt = now
        return true
    }

    private func shouldForcePeriodicLeaderboardWindowRefresh(now: Date) -> Bool {
        guard leaderboardWindow != nil else { return false }

        if let lastPeriodicLeaderboardWindowRefreshAt,
           now.timeIntervalSince(lastPeriodicLeaderboardWindowRefreshAt) < 5 {
            return false
        }

        lastPeriodicLeaderboardWindowRefreshAt = now
        return true
    }

    private func beginLiveActivity() async {
        await liveActivityManager.start(
            climb: mode.climb,
            sessionID: liveActivitySessionID,
            sessionTitle: mode.title,
            sessionSubtitle: mode.subtitle,
            targetSteps: mode.targetStepCount ?? 0,
            steps: totalRecordedSteps,
            rank: liveActivityRank,
            rankTotal: leaderboardTotalClimbers,
            duration: displayedDuration,
            progress: liveActivityProgress
        )
    }

    private func updateLiveActivity(
        status: LiveClimbActivityStatus?,
        force: Bool = false
    ) async {
        guard phase == .recording || phase == .saving else { return }

        await liveActivityManager.update(
            steps: totalRecordedSteps,
            rank: liveActivityRank,
            rankTotal: leaderboardTotalClimbers,
            duration: displayedDuration,
            progress: liveActivityProgress,
            status: status,
            force: force
        )
    }

    private var liveActivityRank: Int? {
        currentLeaderboardRank
    }

    private var liveActivityProgress: Double {
        totalProgressFraction
    }

    private struct SavedLiveClimbSession {
        let workout: Workout
        let attemptStatus: ClimbAttemptStatus
    }

    private func saveWorkout(
        from result: HeadphoneMotionSessionResult,
        splitCurve: LiveReplaySplitCurve,
        modelContext: ModelContext
    ) throws -> SavedLiveClimbSession {
        var attempt: ClimbAttempt?
        if let climb = mode.climb {
            attempt = try climbService.prepareLiveClimbAttempt(
                for: climb,
                startedAt: result.startedAt,
                modelContext: modelContext
            )
        }

        let floors = Workout.stepsToFloors(result.steps)
        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: result.sampleCount,
            trackingMode: mode.trackingMode,
            climbId: mode.climb?.id,
            targetStepCount: targetRemainingSteps,
            climbTargetStepCount: mode.climb?.referenceStepCount,
            targetDurationSeconds: mode.targetDuration,
            stopReason: result.stopReason,
            splitCurve: splitCurve,
            trackingIntegrity: result.trackingIntegrity,
            stepCorrections: result.stepCorrections,
            heartRateCoverage: HeartRateTraceCoverage(
                samples: heartRateRecorder.samples,
                sessionStartedAt: result.startedAt,
                sessionDuration: result.duration
            )
        )

        let heartRateSummary = heartRateWorkoutSummary

        let workout = Workout(
            name: mode.workoutName,
            date: result.startedAt,
            duration: max(result.duration, 1),
            steps: result.steps,
            floors: floors,
            stepsPerFloor: Workout.defaultStepsPerFloor,
            avgHeartRate: heartRateSummary.averageHeartRate,
            maxHeartRate: heartRateSummary.maximumHeartRate,
            heartRateTimeSeries: heartRateSummary.timeSeries,
            source: .headphoneMotion,
            deviceModel: UIDevice.current.model,
            sourceMetadata: metadata.jsonString
        )

        modelContext.insert(workout)
        try modelContext.save()

        var settledAttempt: ClimbAttempt?
        if mode.isLandmarkClimb {
            settledAttempt = try climbService.apply(workouts: [workout], modelContext: modelContext)
        }

        try WorkoutMutationHandler.shared.workoutsDidChange(
            modelContext: modelContext,
            mutation: .created([LeaderboardWorkoutSnapshot(workout: workout)]),
            newWorkouts: [workout],
            changedWorkouts: [workout]
        )
        AppleHealthEnrichmentService.shared.trackNewlyRecordedWorkout(
            workout,
            modelContext: modelContext
        )

        // Just Climb sessions have no attempt to rank - saving one is the finish.
        return SavedLiveClimbSession(
            workout: workout,
            attemptStatus: settledAttempt?.status ?? attempt?.status ?? .completed
        )
    }

    private func trackSavedAttempt(
        result: HeadphoneMotionSessionResult,
        status: ClimbAttemptStatus
    ) {
        let durationSeconds = Int(result.duration.rounded(.down))

        if case .justClimb(let goal) = mode {
            TelemetryManager.shared.track(
                WorkoutSessionAnalyticsEvent.justClimbSaved(
                    context: JustClimbAnalyticsContext(
                        goal: goal,
                        entryPoint: analyticsEntryPoint
                    ),
                    durationSeconds: durationSeconds,
                    steps: result.steps,
                    progressFraction: totalProgressFraction,
                    stopReason: result.stopReason.rawValue,
                    correctionCount: result.stepCorrections.count,
                    trackingUnavailableSeconds: Int(result.trackingIntegrity.totalUnavailableDuration.rounded(.down))
                )
            )
            return
        }

        guard let climb = mode.climb else { return }

        switch status {
        case .completed:
            TelemetryManager.shared.track(
                LiveClimbAnalyticsEvent.attemptCompleted(
                    climb: climb,
                    entryPoint: analyticsEntryPoint,
                    durationSeconds: durationSeconds,
                    steps: result.steps,
                    rank: completionLeaderboardRank,
                    rankTotal: completionLeaderboardTotal
                )
            )
        case .active, .failed, .abandoned:
            TelemetryManager.shared.track(
                LiveClimbAnalyticsEvent.attemptSaved(
                    climb: climb,
                    entryPoint: analyticsEntryPoint,
                    outcome: LiveClimbAnalyticsEvent.AttemptOutcome(status: status),
                    durationSeconds: durationSeconds,
                    steps: result.steps,
                    progressFraction: totalProgressFraction
                )
            )
        }
    }
}
