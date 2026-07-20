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
    private var heartRateSamples: [HeartRateDataPoint] = []
    private var lastHeartRateSampleAt: Date?

    private var hasSavedSession = false
    private var stepTimelineRecorder: LiveClimbStepTimelineRecorder
    private var isLeaderboardRefreshInFlight = false
    private var lastExhaustedLeaderboardWindowRefreshAt: Date?
    private var lastPeriodicLeaderboardWindowRefreshAt: Date?
    private var promptedStepSyncInterruptionCounts: Set<Int> = []
    private var skippedStepSyncInterruptionCounts: Set<Int> = []
    private let stepSyncPromptMinimumGapDuration: TimeInterval = 20
    private var activeDraft: ActiveHeadphoneWorkoutDraft?
    private var lastDraftCheckpointAt: Date?
    private let draftCheckpointInterval: TimeInterval = 2

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
        heartRateMonitor: HeartRateMonitorService = .shared,
        liveActivitySessionID: String = UUID().uuidString,
        recoveredDraft: ActiveHeadphoneWorkoutDraft? = nil
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
        self.heartRateMonitor = heartRateMonitor
        self.activeDraft = recoveredDraft
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
        heartRateMonitor: HeartRateMonitorService = .shared,
        liveActivitySessionID: String = UUID().uuidString,
        recoveredDraft: ActiveHeadphoneWorkoutDraft? = nil
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
        self.heartRateMonitor = heartRateMonitor
        self.activeDraft = recoveredDraft
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
                    steps: totalRecordedSteps
                )
            ]
        }

        return leaderboardWindow.locallyRankedRows(
            currentSteps: totalRecordedSteps,
            currentElapsedSeconds: Int(displayedDuration.rounded(.down))
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

    var leaderboardTotalClimbers: Int {
        max(leaderboardWindow?.totalClimbers ?? 0, leaderboardSummary.totalClimbers)
    }

    var leaderboardCompletedCount: Int {
        leaderboardSummary.completedCount
    }

    var leaderboardUpdatedElapsedSeconds: Int? {
        leaderboardWindow?.bucketElapsedSeconds
    }

    var currentLeaderboardRank: Int? {
        leaderboardRows.first(where: \.isCurrentUser)?.rank ?? leaderboardWindow?.currentUserRank
    }

    var currentRankDisplay: String {
        currentLeaderboardRank.map { "#\($0)" } ?? "—"
    }

    var completionLeaderboardRank: Int? {
        leaderboardWindow?.currentUserRank ?? leaderboardRows.first(where: \.isCurrentUser)?.rank
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
        heartRateSamples.removeAll()
        lastHeartRateSampleAt = nil
        heartRateMonitor.autoConnectIfRemembered()
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
        recordHeartRateSampleIfFresh()
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
            freshMeasurement: heartRateMonitor.freshMeasurement,
            zoneProfile: heartRateZoneProfile
        )
    }

    /// Buffers one reading per second-tick while recording so completed
    /// workouts carry the same heart-rate series shape as imported ones —
    /// the existing sync pipeline uploads it with zero extra plumbing.
    private func recordHeartRateSampleIfFresh() {
        guard let measurement = heartRateMonitor.freshMeasurement else { return }

        let now = Date()
        if let lastHeartRateSampleAt, now.timeIntervalSince(lastHeartRateSampleAt) < 0.9 {
            return
        }
        lastHeartRateSampleAt = now
        heartRateSamples.append(
            HeartRateDataPoint(timestamp: now, heartRate: measurement.beatsPerMinute)
        )
    }

    func checkpointForLifecycleChange(modelContext: ModelContext) {
        guard phase == .recording,
              motionSession.status.isRecording else { return }

        let curve = stepTimelineRecorder.record(
            elapsedSeconds: Int(motionSession.duration.rounded(.down)),
            cumulativeSteps: motionSession.stepCount,
            source: .headphoneMotion
        )
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
        guard phase == .recording,
              !isLeaderboardRefreshInFlight else {
            return
        }

        let now = Date()
        let forceFreshWindow = force ||
            shouldForceFreshLeaderboardWindowRefresh(now: now) ||
            shouldForcePeriodicLeaderboardWindowRefresh(now: now)

        isLeaderboardRefreshInFlight = true
        defer { isLeaderboardRefreshInFlight = false }

        recordLiveSplitSample()

        do {
#if DEBUG
            let refreshStartedAt = Date()
#endif
            if force {
                leaderboardSummary = try await leaderboardService.fetchSummary(context: replayContext)
            }

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

        activeDraft.applyCheckpoint(
            steps: result?.steps ?? totalRecordedSteps,
            durationSeconds: result?.duration ?? displayedDuration,
            sampleCount: result?.sampleCount ?? motionSession.sampleCount,
            splitCurve: splitCurve ?? stepTimelineRecorder.curve,
            trackingIntegrity: result?.trackingIntegrity ?? motionSession.trackingIntegrity,
            stepCorrections: result?.stepCorrections ?? motionSession.stepCorrectionsSnapshot,
            status: status,
            checkpointedAt: now
        )
        do {
            try modelContext.save()
            lastDraftCheckpointAt = now
        } catch {
#if DEBUG
            debugLog("Active headphone draft checkpoint failed: \(error.localizedDescription)")
#endif
        }
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
            stepCorrections: result.stepCorrections
        )

        let heartRates = heartRateSamples.map(\.heartRate)
        let averageHeartRate = heartRates.isEmpty
            ? nil
            : heartRates.reduce(0, +) / heartRates.count

        let workout = Workout(
            name: mode.workoutName,
            date: result.startedAt,
            duration: max(result.duration, 1),
            steps: result.steps,
            floors: floors,
            stepsPerFloor: Workout.defaultStepsPerFloor,
            avgHeartRate: averageHeartRate,
            maxHeartRate: heartRates.max(),
            heartRateTimeSeries: heartRateSamples.isEmpty ? nil : heartRateSamples,
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
        Task { @MainActor in
            await WorkoutImportCoordinator.shared.enrichInAppWorkoutWithAppleHealthIfPossible(
                workout,
                modelContext: modelContext
            )
        }

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
