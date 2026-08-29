import Combine
import Foundation
import SwiftData
import UIKit

@MainActor
@Observable
final class ActiveRoutineViewModel {
    let routine: Routine
    let intervals: [RoutineInterval]
    let totalDuration: TimeInterval

    private let replayContext: LiveReplayLeaderboardContext
    private let leaderboardService: LiveReplayLeaderboardServicing
    private let motionSession: HeadphoneMotionSessionService
    private let backgroundSessionService: LiveClimbBackgroundSessionService
    private let draftStore: ActiveHeadphoneWorkoutDraftStore
    private let heartRateRecorder: LiveHeartRateRecorder
    /// Read once per session. `leaderboardRows` is rebuilt on every step and
    /// elapsed tick, so the climber's name cannot be resolved from the cache
    /// inside it.
    private let currentUserDisplayName = UserDataRepository.shared.getCachedDisplayName()

    var phase: ActiveRoutinePhase = .countdown
    var countdownValue = 3
    var currentIntervalIndex = 0
    var elapsedInInterval: TimeInterval = 0
    var actualElapsed: TimeInterval = 0
    var timelineElapsed: TimeInterval = 0
    var sessionStartedAt: Date?
    var isPaused = false
    var showStopConfirmation = false
    var showCompletionSheet = false
    var errorMessage: String?
    private(set) var leaderboardWindow: LiveReplayLeaderboardWindow?
    private(set) var leaderboardFetchFailed = false
    private(set) var recordedResult: HeadphoneMotionSessionResult?
    private(set) var savedWorkout: Workout?
    private(set) var skippedIntervalCount = 0
    private(set) var stepSyncPrompt: RoutineStepSyncPrompt?
    private(set) var stepSyncConfirmation: RoutineStepSyncConfirmation?

    private var countdownStartDate: Date?
    private var lastTickDate: Date?
    private var lastCountdownHapticValue: Int?
    private var lastWarningSecond: Int?
    @ObservationIgnored private var timerCancellable: AnyCancellable?
    private var modelContext: ModelContext?
    private(set) var hasRecordedCompletion = false
    private var hasTrackedSessionStart = false
    private var hasTrackedSessionCompletion = false
    private var stepTimelineRecorder = LiveClimbStepTimelineRecorder(intervalSeconds: 10)
    private var activeDraft: ActiveHeadphoneWorkoutDraft?
    private var lastDraftCheckpointAt: Date?
    private let draftCheckpointInterval: TimeInterval = 2
    private var promptedStepSyncInterruptionCounts: Set<Int> = []
    private var skippedStepSyncInterruptionCounts: Set<Int> = []
    private let stepSyncPromptMinimumGapDuration: TimeInterval = 20

    init(
        routine: Routine,
        leaderboardService: LiveReplayLeaderboardServicing = LiveReplayLeaderboardService.shared,
        motionSession: HeadphoneMotionSessionService = HeadphoneMotionSessionService(),
        backgroundSessionService: LiveClimbBackgroundSessionService = .shared,
        draftStore: ActiveHeadphoneWorkoutDraftStore = ActiveHeadphoneWorkoutDraftStore(),
        heartRateRecorder: LiveHeartRateRecorder = LiveHeartRateRecorder(),
        recoveredDraft: ActiveHeadphoneWorkoutDraft? = nil
    ) {
        self.routine = routine
        intervals = routine.intervals
        totalDuration = routine.totalDuration
        replayContext = RoutineReplayLeaderboardContextBuilder.context(for: routine)
        self.leaderboardService = leaderboardService
        self.motionSession = motionSession
        self.backgroundSessionService = backgroundSessionService
        self.draftStore = draftStore
        self.heartRateRecorder = heartRateRecorder
        self.activeDraft = recoveredDraft
    }

    var currentInterval: RoutineInterval? {
        guard currentIntervalIndex < intervals.count else { return nil }
        return intervals[currentIntervalIndex]
    }

    var remainingInInterval: TimeInterval {
        guard let currentInterval else { return 0 }
        return max(0, currentInterval.duration - elapsedInInterval)
    }

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return min(max(timelineElapsed / totalDuration, 0), 1)
    }

    var currentLevelText: String {
        currentInterval?.intensityDisplay ?? "--"
    }

    var currentStepTypeText: String? {
        guard let currentInterval else { return nil }
        let stepType = currentInterval.modifiers.stepTypeDescription
        return stepType == "Standard step" ? nil : stepType
    }

    var staircaseStepCount: Int {
        intervals.count
    }

    var staircaseActiveIndex: Int {
        min(max(currentIntervalIndex, 0), max(intervals.count - 1, 0))
    }

    var formattedElapsed: String {
        formatClockTime(timelineElapsed)
    }

    var formattedTotalDuration: String {
        formatClockTime(totalDuration)
    }

    var formattedRemainingInInterval: String {
        formatClockTime(remainingInInterval)
    }

    var targetStepGoal: Int {
        replayContext.targetSteps
    }

    var currentSteps: Int {
        recordedResult?.steps ?? motionSession.stepCount
    }

    var shouldShowTrackingRecoveryStatus: Bool {
        phase == .active && motionSession.trackingIntegrity.shouldShowRecoveryStatus
    }

    var leaderboardRows: [LiveReplayLeaderboardRow] {
        guard let leaderboardWindow else {
            return [
                LiveReplayLeaderboardRow.currentUser(
                    rank: nil,
                    steps: currentSteps,
                    displayName: currentUserDisplayName
                )
            ]
        }

        return leaderboardWindow.locallyRankedRows(
            currentSteps: currentSteps,
            currentElapsedSeconds: Int(timelineElapsed.rounded(.down)),
            displayName: currentUserDisplayName
        )
    }

    var leaderboardProgressScale: Int {
        let fetchedMaxSteps = leaderboardWindow?.rows.map(\.finalSteps).max() ?? 0
        return max(max(targetStepGoal, fetchedMaxSteps), currentSteps)
    }

    var leaderboardCurrentProgressFraction: Double {
        guard leaderboardProgressScale > 0 else { return 0 }
        return min(max(Double(currentSteps) / Double(leaderboardProgressScale), 0), 1)
    }

    /// A forfeited session never holds a standing, so it must not render one.
    private var earnsRoutineStanding: Bool {
        routine.source.isTemplate && countsAsCompletion
    }

    var completionLeaderboardContext: LiveReplayLeaderboardContext? {
        earnsRoutineStanding ? replayContext : nil
    }

    var completionLeaderboardRank: Int? {
        guard earnsRoutineStanding else { return nil }
        return leaderboardWindow?.currentUserRank ?? leaderboardRows.first(where: \.isLiveAttempt)?.rank
    }

    var completionLeaderboardTotal: Int? {
        guard earnsRoutineStanding,
              let leaderboardWindow else { return nil }
        let total = max(leaderboardWindow.totalClimbers, leaderboardRows.count)
        return total > 0 ? total : nil
    }

    var completionSummaryPresentation: RoutineCompletionSummaryPresentation {
        RoutineCompletionSummaryPresentation(
            stopReason: resolvedStopReason,
            hasRoutineLeaderboard: completionLeaderboardContext != nil
        )
    }

    /// Reads `resolvedStopReason` so the funnel reports the same outcome the participation record
    /// and the summary were built from, rather than a second derivation that can disagree.
    var sessionCompletionAnalyticsEvent: WorkoutSessionAnalyticsEvent {
        .routineCompleted(
            context: analyticsContext,
            durationSeconds: analyticsDurationSeconds,
            steps: currentSteps,
            progressFraction: progress,
            stopReason: resolvedStopReason.rawValue
        )
    }

    var currentIntervalPositionText: String {
        guard !intervals.isEmpty else { return "No intervals" }
        let displayIndex = min(max(currentIntervalIndex + 1, 1), intervals.count)
        return "Interval \(displayIndex) of \(intervals.count)"
    }

    var isNearIntervalEnd: Bool {
        remainingInInterval <= 3 && remainingInInterval > 0
    }

    var didSkipInterval: Bool {
        skippedIntervalCount > 0
    }

    /// Reaching the end of the interval list only earns competitive credit when the climber
    /// actually stepped through every interval. Skipping burns the clock without steps, so a
    /// session containing any skip finishes as `.skipped` and stays out of the replay index.
    var completionStopReason: HeadphoneMotionSessionStopReason {
        didSkipInterval ? .skipped : .targetReached
    }

    /// The stop reason the session actually ended on, which is the same value the participation
    /// record is built from. Reading it here keeps the summary from contradicting the record.
    var resolvedStopReason: HeadphoneMotionSessionStopReason {
        recordedResult?.stopReason ?? completionStopReason
    }

    var countsAsCompletion: Bool {
        resolvedStopReason.earnsCompetitiveCredit
    }

    func startSession(modelContext: ModelContext) {
        AppDiagnosticsRecorder.shared.record(
            "routine_headphone_session_start_requested",
            details: [
                "routine_id": routine.id.uuidString,
                "resumed_from_draft": activeDraft == nil ? "false" : "true"
            ]
        )
        stopTimer()
        heartRateRecorder.prepareForSession()
        self.modelContext = modelContext
        phase = .countdown
        countdownValue = 3
        if let activeDraft {
            restoreTimeline(to: activeDraft.durationSeconds)
            actualElapsed = activeDraft.durationSeconds
            sessionStartedAt = activeDraft.startedAt
            recordedResult = nil
            savedWorkout = nil
            skippedIntervalCount = activeDraft.routineSkippedIntervalCount ?? 0
            if let splitCurve = activeDraft.splitCurve {
                stepTimelineRecorder.restore(curve: splitCurve)
            }
        } else {
            currentIntervalIndex = 0
            elapsedInInterval = 0
            actualElapsed = 0
            timelineElapsed = 0
            sessionStartedAt = nil
            recordedResult = nil
            savedWorkout = nil
            skippedIntervalCount = 0
            stepTimelineRecorder.reset()
            stepTimelineRecorder.record(
                elapsedSeconds: 0,
                cumulativeSteps: 0,
                source: .headphoneMotion
            )
        }
        isPaused = false
        showCompletionSheet = false
        errorMessage = nil
        leaderboardWindow = nil
        leaderboardFetchFailed = false
        stepSyncPrompt = nil
        stepSyncConfirmation = nil
        promptedStepSyncInterruptionCounts.removeAll(keepingCapacity: true)
        skippedStepSyncInterruptionCounts.removeAll(keepingCapacity: true)
        countdownStartDate = Date()
        lastTickDate = nil
        lastCountdownHapticValue = 3
        lastWarningSecond = nil
        hasRecordedCompletion = false
        hasTrackedSessionStart = false
        hasTrackedSessionCompletion = false
        startTimer()
        HapticsManager.shared.trigger(.mediumImpact)
    }

    func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    func handleTick(at now: Date) {
        switch phase {
        case .countdown:
            updateCountdown(at: now)
        case .active:
            updateActiveSession(at: now)
        case .finishing, .saving, .complete, .failed:
            break
        }
    }

    func togglePause() {
        isPaused.toggle()
        lastTickDate = nil
        do {
            if isPaused {
                try motionSession.pauseRecording()
            } else {
                try motionSession.resumeRecording()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        HapticsManager.shared.trigger(.mediumImpact)
    }

    func skipInterval() {
        guard let currentInterval else { return }

        let remainingTimeline = max(currentInterval.duration - elapsedInInterval, 0)
        timelineElapsed += remainingTimeline
        elapsedInInterval = 0
        lastWarningSecond = nil
        currentIntervalIndex += 1
        skippedIntervalCount += 1
        lastTickDate = Date()

        if currentIntervalIndex >= intervals.count {
            completeWorkout()
        } else {
            checkpointDraft(force: true)
            HapticsManager.shared.trigger(.heavyImpact)
        }
    }

    func markCompletionRecorded() {
        hasRecordedCompletion = true
    }

    func trackLogWorkoutTapped(surface: WorkoutSessionAnalyticsEvent.RoutineSurface) {
        TelemetryManager.shared.track(
            WorkoutSessionAnalyticsEvent.routineLogTapped(
                context: analyticsContext,
                surface: surface,
                durationSeconds: analyticsDurationSeconds,
                steps: currentSteps,
                progressFraction: progress
            )
        )
    }

    func trackWorkoutSaved(_ workout: Workout) {
        TelemetryManager.shared.track(
            WorkoutSessionAnalyticsEvent.routineSaved(
                context: analyticsContext,
                durationSeconds: Int(workout.duration.rounded(.down)),
                steps: workout.steps,
                progressFraction: progress
            )
        )
    }

    func trackDiscard(surface: WorkoutSessionAnalyticsEvent.RoutineSurface) {
        TelemetryManager.shared.track(
            WorkoutSessionAnalyticsEvent.routineDiscarded(
                context: analyticsContext,
                surface: surface,
                durationSeconds: analyticsDurationSeconds,
                steps: currentSteps,
                progressFraction: progress
            )
        )
    }

    func evaluateStepSyncPrompt() {
        guard phase == .active,
              stepSyncPrompt == nil,
              motionSession.sampleCount > 0,
              !motionSession.trackingIntegrity.isCurrentlyUnavailable,
              let resolvedGap = motionSession.lastResolvedTrackingGap,
              resolvedGap.duration >= stepSyncPromptMinimumGapDuration,
              resolvedGap.interruptionCount > 0,
              !promptedStepSyncInterruptionCounts.contains(resolvedGap.interruptionCount),
              !skippedStepSyncInterruptionCounts.contains(resolvedGap.interruptionCount) else {
            return
        }

        promptedStepSyncInterruptionCounts.insert(resolvedGap.interruptionCount)
        stepSyncPrompt = RoutineStepSyncPrompt(
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
        stepSyncConfirmation = RoutineStepSyncConfirmation(correctedSteps: correction.correctedSteps)
        checkpointDraft(force: true)

        Task { [weak self] in
            await self?.refreshReplayLeaderboardIfNeeded(force: true)
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

    func refreshReplayLeaderboardIfNeeded(force: Bool = false) async {
        guard phase == .active || phase == .complete else { return }

        do {
            let window = try await leaderboardService.refreshIfNeeded(
                context: replayContext,
                elapsedSeconds: Int(timelineElapsed.rounded(.down)),
                currentSteps: currentSteps,
                force: force
            )

            if let window {
                leaderboardWindow = window
            }

            leaderboardFetchFailed = false
        } catch {
            leaderboardFetchFailed = true
        }
    }

    func saveRecordedWorkout(
        modelContext: ModelContext,
        reason: HeadphoneMotionSessionStopReason = .userStopped
    ) async throws -> Workout {
        guard phase != .saving else {
            if let savedWorkout { return savedWorkout }
            throw ActiveRoutineSessionError.saveInProgress
        }

        if recordedResult == nil {
            await finishRecording(reason: reason, showCompletion: false)
        }

        guard let result = recordedResult else {
            throw ActiveRoutineSessionError.noRecordedResult
        }
        guard result.hasRecordedSteps else {
            throw ActiveRoutineSessionError.noStepsRecorded
        }

        phase = .saving
        errorMessage = nil

        let splitCurve = stepTimelineRecorder.curve
        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: result.sampleCount,
            trackingMode: .routine,
            climbId: nil,
            routineId: routine.id.uuidString,
            routineTemplateId: routine.templateId,
            // Frozen with the session: a card that says 8 intervals has to mean
            // this session ran 8, not that the routine holds 8 today.
            routineIntervalCount: routine.intervalCount,
            targetStepCount: targetStepGoal,
            targetDurationSeconds: totalDuration,
            stopReason: result.stopReason,
            splitCurve: splitCurve,
            trackingIntegrity: result.trackingIntegrity,
            stepCorrections: result.stepCorrections
        )
        let heartRateSummary = heartRateWorkoutSummary
        let workout = Workout(
            name: routine.name,
            date: result.startedAt,
            duration: max(result.duration, 1),
            steps: result.steps,
            floors: Workout.stepsToFloors(result.steps),
            stepsPerFloor: Workout.defaultStepsPerFloor,
            avgHeartRate: heartRateSummary.averageHeartRate,
            maxHeartRate: heartRateSummary.maximumHeartRate,
            heartRateTimeSeries: heartRateSummary.timeSeries,
            source: .headphoneMotion,
            deviceModel: UIDevice.current.model,
            sourceMetadata: metadata.jsonString,
            weightConfiguration: routine.defaultWeightConfiguration
        )

        modelContext.insert(workout)
        try modelContext.save()
        try WorkoutParticipationService.addRoutineParticipationIfNeeded(
            for: workout,
            attribution: RoutineWorkoutAttribution(
                routineId: routine.id,
                routineSource: routine.source,
                templateId: routine.templateId,
                origin: .liveSession(stopReason: result.stopReason)
            ),
            userId: workout.ownerUserId,
            modelContext: modelContext
        )
        try modelContext.save()
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

        savedWorkout = workout
        phase = .complete
        clearDraft(modelContext: modelContext)
        trackWorkoutSaved(workout)
        AppDiagnosticsRecorder.shared.record(
            "routine_headphone_session_saved",
            details: [
                "routine_id": routine.id.uuidString,
                "steps": String(workout.steps),
                "duration_seconds": String(Int(workout.duration.rounded(.down)))
            ]
        )
        return workout
    }

    func discard(modelContext: ModelContext) async {
        if motionSession.status.isRecording || motionSession.status.isPaused {
            _ = try? await motionSession.stopRecording(reason: .discarded)
        }
        AppDiagnosticsRecorder.shared.record(
            "routine_headphone_session_discarded",
            details: [
                "routine_id": routine.id.uuidString,
                "steps": String(currentSteps),
                "duration_seconds": String(Int(actualElapsed.rounded(.down)))
            ]
        )
        backgroundSessionService.stop()
        clearDraft(modelContext: modelContext)
    }

    func checkpointForLifecycleChange() {
        guard phase == .active || phase == .finishing else { return }

        recordLiveSplitSample()
        checkpointDraft(force: true)
        AppDiagnosticsRecorder.shared.record(
            "routine_headphone_session_lifecycle_checkpoint",
            details: [
                "routine_id": routine.id.uuidString,
                "steps": String(currentSteps),
                "duration_seconds": String(Int(actualElapsed.rounded(.down)))
            ]
        )
    }

    private func updateCountdown(at now: Date) {
        guard let startDate = countdownStartDate else {
            countdownStartDate = now
            return
        }

        let elapsed = now.timeIntervalSince(startDate)
        let secondsRemaining = max(0, 3 - Int(floor(elapsed)))
        countdownValue = secondsRemaining

        if secondsRemaining > 0, secondsRemaining != lastCountdownHapticValue {
            lastCountdownHapticValue = secondsRemaining
            HapticsManager.shared.trigger(.mediumImpact)
        }

        if elapsed >= 3 {
            do {
                try beginHeadphoneRecordingIfNeeded(startedAt: now)
            } catch {
                phase = .failed(error.localizedDescription)
                errorMessage = error.localizedDescription
                stopTimer()
                return
            }

            phase = .active
            sessionStartedAt = activeDraft?.startedAt ?? now
            self.countdownStartDate = nil
            lastTickDate = now
            trackSessionStartIfNeeded()
            HapticsManager.shared.trigger(.heavyImpact)
        }
    }

    private func updateActiveSession(at now: Date) {
        guard !isPaused, currentInterval != nil else {
            lastTickDate = now
            return
        }

        guard let lastTickDate else {
            self.lastTickDate = now
            return
        }

        let delta = min(max(now.timeIntervalSince(lastTickDate), 0), 0.25)
        self.lastTickDate = now

        guard delta > 0 else { return }

        elapsedInInterval += delta
        actualElapsed = motionSession.duration
        timelineElapsed += delta
        recordLiveSplitSample(at: now)
        checkpointDraft()
        evaluateStepSyncPrompt()

        triggerEndOfIntervalWarningsIfNeeded()

        while let currentInterval, elapsedInInterval >= currentInterval.duration {
            let overflow = elapsedInInterval - currentInterval.duration
            currentIntervalIndex += 1
            elapsedInInterval = max(0, overflow)
            lastWarningSecond = nil

            if currentIntervalIndex >= intervals.count {
                completeWorkout()
                return
            } else {
                HapticsManager.shared.trigger(.heavyImpact)
            }
        }
    }

    private func triggerEndOfIntervalWarningsIfNeeded() {
        let wholeSecondsRemaining = Int(ceil(remainingInInterval))
        guard wholeSecondsRemaining > 0, wholeSecondsRemaining <= 3 else { return }
        guard wholeSecondsRemaining != lastWarningSecond else { return }

        lastWarningSecond = wholeSecondsRemaining
        HapticsManager.shared.trigger(.lightImpact)
    }

    private func completeWorkout() {
        stopTimer()
        phase = .finishing
        isPaused = false
        lastTickDate = nil
        lastWarningSecond = nil
        Task { @MainActor in
            await finishRecording(reason: completionStopReason, showCompletion: true)
        }
    }

    private func beginHeadphoneRecordingIfNeeded(startedAt: Date) throws {
        guard !motionSession.status.isRecording else { return }
        guard let modelContext else {
            throw ActiveRoutineSessionError.missingModelContext
        }

        let preexistingDraft = activeDraft
        AppDiagnosticsRecorder.shared.record(
            "routine_headphone_recording_start_requested",
            details: [
                "routine_id": routine.id.uuidString,
                "resumed_from_draft": preexistingDraft == nil ? "false" : "true"
            ]
        )
        do {
            let draft = try prepareDraftIfNeeded(startedAt: startedAt, modelContext: modelContext)
            try motionSession.startRecording(resumeState: draft?.resumeState)
            backgroundSessionService.start(at: draft?.startedAt ?? startedAt)
            recordLiveSplitSample()
            checkpointDraft(force: true)
            AppDiagnosticsRecorder.shared.record(
                "routine_headphone_recording_started",
                details: draft?.diagnosticDetails ?? ["routine_id": routine.id.uuidString]
            )
        } catch {
            if preexistingDraft == nil,
               let activeDraft,
               activeDraft.steps == 0 {
                ActiveHeadphoneWorkoutRuntimeRegistry.shared.markInactive(activeDraft)
                try? draftStore.delete(activeDraft, in: modelContext)
                self.activeDraft = nil
            }
            AppDiagnosticsRecorder.shared.record(
                "routine_headphone_recording_start_failed",
                level: .error,
                details: [
                    "routine_id": routine.id.uuidString,
                    "error": error.localizedDescription
                ]
            )
            throw error
        }
    }

    private func prepareDraftIfNeeded(
        startedAt: Date,
        modelContext: ModelContext
    ) throws -> ActiveHeadphoneWorkoutDraft? {
        if let activeDraft {
            draftStore.setActiveDraftID(activeDraft.id)
            ActiveHeadphoneWorkoutRuntimeRegistry.shared.markActive(activeDraft)
            return activeDraft
        }

        let draft = ActiveHeadphoneWorkoutDraft(
            sessionID: UUID().uuidString,
            kind: .routine,
            startedAt: startedAt,
            title: routine.name,
            subtitle: routine.totalDurationFormatted,
            workoutName: routine.name,
            targetStepCount: targetStepGoal,
            targetDurationSeconds: totalDuration,
            routineId: routine.id,
            routineSource: routine.source,
            routineTemplateId: routine.templateId,
            routineDifficulty: routine.difficulty,
            routineIntervalCount: routine.intervalCount,
            routineWeightConfiguration: routine.defaultWeightConfiguration
        )
        try draftStore.insert(draft, in: modelContext)
        activeDraft = draft
        ActiveHeadphoneWorkoutRuntimeRegistry.shared.markActive(draft)
        return draft
    }

    private func finishRecording(
        reason: HeadphoneMotionSessionStopReason,
        showCompletion: Bool
    ) async {
        guard recordedResult == nil else {
            if showCompletion {
                phase = .complete
                showCompletionSheet = true
                trackSessionCompletionIfNeeded()
                HapticsManager.shared.trigger(.success)
            }
            return
        }

        do {
            let result: HeadphoneMotionSessionResult
            if motionSession.status.isRecording || motionSession.status.isPaused {
                result = try await motionSession.stopRecording(reason: reason)
            } else if let activeDraft {
                result = HeadphoneMotionSessionResult(
                    startedAt: activeDraft.startedAt,
                    endedAt: activeDraft.lastCheckpointAt,
                    duration: activeDraft.durationSeconds,
                    steps: activeDraft.steps,
                    sampleCount: activeDraft.sampleCount,
                    stopReason: reason,
                    trackingIntegrity: activeDraft.trackingIntegrity,
                    stepCorrections: activeDraft.stepCorrections
                )
            } else {
                throw ActiveRoutineSessionError.noRecordedResult
            }

            let finalSplitCurve = stepTimelineRecorder.record(
                elapsedSeconds: Int(result.duration.rounded(.down)),
                cumulativeSteps: result.steps,
                source: .headphoneMotion
            )
            recordedResult = result
            actualElapsed = result.duration
            checkpointDraft(
                splitCurve: finalSplitCurve,
                result: result,
                status: .stopped,
                force: true
            )
            backgroundSessionService.stop()
            phase = .complete

            if showCompletion {
                showCompletionSheet = true
                trackSessionCompletionIfNeeded()
                HapticsManager.shared.trigger(.success)
            }
            AppDiagnosticsRecorder.shared.record(
                "routine_headphone_recording_finished",
                details: [
                    "routine_id": routine.id.uuidString,
                    "reason": reason.rawValue,
                    "steps": String(result.steps),
                    "duration_seconds": String(Int(result.duration.rounded(.down)))
                ]
            )
        } catch {
            backgroundSessionService.stop()
            phase = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
            AppDiagnosticsRecorder.shared.record(
                "routine_headphone_recording_finish_failed",
                level: .error,
                details: [
                    "routine_id": routine.id.uuidString,
                    "reason": reason.rawValue,
                    "error": error.localizedDescription
                ]
            )
        }
    }

    private func recordLiveSplitSample(at now: Date = Date()) {
        guard phase == .active || phase == .finishing else { return }

        _ = stepTimelineRecorder.record(
            elapsedSeconds: Int(motionSession.duration.rounded(.down)),
            cumulativeSteps: motionSession.stepCount,
            source: .headphoneMotion
        )
        recordHeartRateSampleForSessionTick(at: now)
    }

    func recordHeartRateSampleForSessionTick(at now: Date = Date()) {
        heartRateRecorder.recordSample(at: now)
    }

    var heartRateWorkoutSummary: LiveHeartRateWorkoutSummary {
        heartRateRecorder.workoutSummary
    }

    private func checkpointDraft(
        splitCurve: LiveReplaySplitCurve? = nil,
        result: HeadphoneMotionSessionResult? = nil,
        status: ActiveHeadphoneWorkoutDraftStatus = .recording,
        force: Bool = false
    ) {
        guard let modelContext,
              let activeDraft else { return }

        let now = Date()
        if !force,
           let lastDraftCheckpointAt,
           now.timeIntervalSince(lastDraftCheckpointAt) < draftCheckpointInterval {
            return
        }

        activeDraft.applyCheckpoint(
            steps: result?.steps ?? currentSteps,
            durationSeconds: result?.duration ?? motionSession.duration,
            sampleCount: result?.sampleCount ?? motionSession.sampleCount,
            splitCurve: splitCurve ?? stepTimelineRecorder.curve,
            trackingIntegrity: result?.trackingIntegrity ?? motionSession.trackingIntegrity,
            stepCorrections: result?.stepCorrections ?? motionSession.stepCorrectionsSnapshot,
            status: status,
            skippedIntervalCount: skippedIntervalCount,
            checkpointedAt: now
        )

        do {
            try modelContext.save()
            lastDraftCheckpointAt = now
        } catch {
#if DEBUG
            debugLog("Routine draft checkpoint failed: \(error.localizedDescription)")
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
            debugLog("Routine draft cleanup failed: \(error.localizedDescription)")
#endif
            draftStore.clearActiveDraftID(activeDraft.id)
        }
        self.activeDraft = nil
        lastDraftCheckpointAt = nil
    }

    private func restoreTimeline(to elapsed: TimeInterval) {
        let clampedElapsed = min(max(elapsed, 0), totalDuration)
        timelineElapsed = clampedElapsed
        currentIntervalIndex = 0
        elapsedInInterval = 0

        var remainingElapsed = clampedElapsed
        for (index, interval) in intervals.enumerated() {
            if remainingElapsed >= interval.duration {
                currentIntervalIndex = index + 1
                remainingElapsed -= interval.duration
            } else {
                currentIntervalIndex = index
                elapsedInInterval = remainingElapsed
                break
            }
        }

        if currentIntervalIndex >= intervals.count {
            currentIntervalIndex = intervals.count
            elapsedInInterval = 0
        }
    }

    private var analyticsContext: RoutineSessionAnalyticsContext {
        RoutineSessionAnalyticsContext(
            routine: routine,
            targetSteps: targetStepGoal
        )
    }

    private var analyticsDurationSeconds: Int {
        Int(actualElapsed.rounded(.down))
    }

    private func trackSessionStartIfNeeded() {
        guard !hasTrackedSessionStart else { return }
        hasTrackedSessionStart = true
        TelemetryManager.shared.track(
            WorkoutSessionAnalyticsEvent.routineStarted(context: analyticsContext)
        )
    }

    private func trackSessionCompletionIfNeeded() {
        guard !hasTrackedSessionCompletion else { return }
        hasTrackedSessionCompletion = true
        TelemetryManager.shared.track(sessionCompletionAnalyticsEvent)
    }

    private func startTimer() {
        timerCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                self?.handleTick(at: now)
            }
    }

    private func formatClockTime(_ interval: TimeInterval) -> String {
        let totalSeconds = max(Int(interval.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
    }
}

enum ActiveRoutinePhase: Equatable {
    case countdown
    case active
    case finishing
    case saving
    case complete
    case failed(String)
}

enum ActiveRoutineSessionError: LocalizedError {
    case missingModelContext
    case noRecordedResult
    case noStepsRecorded
    case saveInProgress

    var errorDescription: String? {
        switch self {
        case .missingModelContext:
            return "Routine tracking is not ready yet."
        case .noRecordedResult:
            return "No routine tracking result was recorded."
        case .noStepsRecorded:
            return "No steps were recorded for this routine."
        case .saveInProgress:
            return "This routine is already saving."
        }
    }
}

struct RoutineStepSyncPrompt: Identifiable, Equatable {
    let id = UUID()
    let detectedSteps: Int
    let gapDuration: TimeInterval
    let interruptionCount: Int
}

struct RoutineStepSyncConfirmation: Identifiable, Equatable {
    let id = UUID()
    let correctedSteps: Int
}
