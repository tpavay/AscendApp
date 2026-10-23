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
    private let motionSession: any HeadphoneMotionSessionServicing
    private let backgroundSessionService: any LiveClimbBackgroundSessionControlling
    /// Whether the countdown started the workout session, so an abandoned countdown stops it.
    private var didPrepareBackgroundSession = false
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
    /// Whether the leaderboard service has been told this session started. A
    /// routine session is a session: what the repository remembers about the
    /// climber's own rows belongs to one session, and the run this one publishes
    /// is what the next one on the same board must not miss. Crossed on the first
    /// window refresh, so it is ordered ahead of that refresh.
    private var hasBegunLeaderboardSession = false
    private var stepTimelineRecorder = LiveClimbStepTimelineRecorder(intervalSeconds: 10)
    /// The one writer of this session's draft, shared with Live Climb and Just Climb
    /// (`docs/headphone-session-recovery.md`).
    let checkpointer: HeadphoneSessionCheckpointer
    private var activeDraft: ActiveHeadphoneWorkoutDraft? {
        checkpointer.activeDraft
    }
    /// Shown over a session resumed after the process died; nil for a fresh session.
    private(set) var resumeNotice: HeadphoneSessionResumeNotice?
    /// A resumed session has already counted its three seconds once; it goes straight to active.
    private var skipsCountdown = false
    /// Set by `startSession`, so a screen that adopts a running session does not start it again.
    private(set) var hasBegunSession = false
    /// The id the draft, the heartbeat and the screen-presence registry all share. Minted here so it
    /// exists before the countdown writes the draft, and reused by a recovered draft.
    let sessionID: String
    /// Injectable so a test can place a session on the day it is reproducing.
    private let now: () -> Date
    private var promptedStepSyncInterruptionCounts: Set<Int> = []
    private var skippedStepSyncInterruptionCounts: Set<Int> = []
    private let stepSyncPromptMinimumGapDuration: TimeInterval = 20

    init(
        routine: Routine,
        leaderboardService: LiveReplayLeaderboardServicing = LiveReplayLeaderboardService.shared,
        motionSession: any HeadphoneMotionSessionServicing = HeadphoneMotionSessionService(),
        backgroundSessionService: any LiveClimbBackgroundSessionControlling = LiveClimbBackgroundSessionService.shared,
        draftStore: ActiveHeadphoneWorkoutDraftStore = ActiveHeadphoneWorkoutDraftStore(),
        heartRateRecorder: LiveHeartRateRecorder = LiveHeartRateRecorder(),
        recoveredDraft: ActiveHeadphoneWorkoutDraft? = nil,
        resumeNotice: HeadphoneSessionResumeNotice? = nil,
        checkpointer: HeadphoneSessionCheckpointer? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.routine = routine
        self.now = now
        intervals = routine.intervals
        totalDuration = routine.totalDuration
        replayContext = RoutineReplayLeaderboardContextBuilder.context(for: routine)
        self.leaderboardService = leaderboardService
        self.motionSession = motionSession
        self.backgroundSessionService = backgroundSessionService
        self.heartRateRecorder = heartRateRecorder
        let resolvedCheckpointer = checkpointer ?? HeadphoneSessionCheckpointer(
            draftStore: draftStore,
            backgroundSession: backgroundSessionService
        )
        resolvedCheckpointer.adopt(recoveredDraft)
        self.checkpointer = resolvedCheckpointer
        self.resumeNotice = resumeNotice
        self.sessionID = recoveredDraft?.sessionID ?? UUID().uuidString
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

    /// Steps stopped because Motion & Fitness is off, not because the headphones dropped out.
    var shouldShowMotionAccessStatus: Bool {
        phase == .active && motionSession.isMotionAccessDenied
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

    /// What this session's board may state about where the climber stands.
    ///
    /// A routine board holds no count it can substantiate, so it names no field;
    /// where nobody else has finished it, the climber's own climbs are the only
    /// population there is and the panel states that rather than a bare ordinal.
    var leaderboardStanding: LiveReplayLiveStanding {
        // A window that has not arrived, and a window that could not count this
        // climber's own history, both state no placing. Neither is "first of
        // one" - see `LiveClimbSessionViewModel.leaderboardStanding`.
        guard let window = leaderboardWindow else {
            return .racing(field: nil, ownClimbs: nil)
        }

        return LiveReplayLiveStanding.resolve(
            field: nil,
            ownClimbs: window.ownClimbs,
            isSoleClimber: window.isSoleClimber
        )
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

    /// Begins the session. A fresh routine counts down from three; a session resumed after the
    /// process died (`skipsCountdown`) is already mid-routine and goes straight back to counting,
    /// with no view required - the background relaunch calls this with nothing on screen.
    func startSession(modelContext: ModelContext, skipsCountdown: Bool = false) {
        AppDiagnosticsRecorder.shared.record(
            "routine_headphone_session_start_requested",
            details: [
                "routine_id": routine.id.uuidString,
                "resumed_from_draft": activeDraft == nil ? "false" : "true",
                "skips_countdown": skipsCountdown ? "true" : "false"
            ]
        )
        self.skipsCountdown = skipsCountdown
        hasBegunSession = true
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
        countdownStartDate = now()
        lastTickDate = nil
        lastCountdownHapticValue = 3
        lastWarningSecond = nil
        hasRecordedCompletion = false
        hasTrackedSessionStart = false
        hasTrackedSessionCompletion = false
        prepareBackgroundSessionForCountdown()
        if skipsCountdown {
            countdownValue = 0
            updateCountdown(at: now(), elapsed: 3)
        }
        startTimer()
        HapticsManager.shared.trigger(.mediumImpact)
    }

    /// Starts the workout session with the countdown rather than at GO, so Apple's one-time
    /// "Health and Fitness Data" notice lands while the climber is still watching the screen, and a
    /// phone locked during the countdown still starts recording on time.
    private func prepareBackgroundSessionForCountdown() {
        guard phase == .countdown, !backgroundSessionService.isRunning else { return }
        backgroundSessionService.start(at: Date())
        didPrepareBackgroundSession = true
    }

    /// Stops a workout session the countdown started when the countdown never reaches GO.
    func cancelPreparedBackgroundSession() {
        guard phase == .countdown, didPrepareBackgroundSession else { return }
        didPrepareBackgroundSession = false
        backgroundSessionService.stop()
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
            checkpointer.checkpoint(makeCheckpointSnapshot(), force: true)
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
        checkpointer.checkpoint(makeCheckpointSnapshot(), force: true)

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

        if !hasBegunLeaderboardSession {
            await leaderboardService.beginLiveSession()
            hasBegunLeaderboardSession = true
        }

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
        checkpointer.publishSessionEnd(outcome: .saved)
        checkpointer.clearDraft()
        ActiveRoutineSessionCoordinator.shared.clearIfActive(sessionID: sessionID)
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
        checkpointer.publishSessionEnd(outcome: .discarded)
        checkpointer.clearDraft()
        ActiveRoutineSessionCoordinator.shared.clearIfActive(sessionID: sessionID)
    }

    func checkpointForLifecycleChange() {
        guard phase == .active || phase == .finishing else { return }

        recordLiveSplitSample()
        checkpointer.checkpointForLifecycleChange(makeCheckpointSnapshot(), kind: ActiveHeadphoneWorkoutDraftKind.routine.rawValue)
    }

    // MARK: - Resume after a process death

    /// Applies the machine count a resumed session's notice collected, as a correction against the
    /// gap, and clears the notice. The view then saves or keeps counting; both paths go through
    /// the routine's ordinary save, so a resumed session finishes the way every other one does.
    func settleResumeNotice(machineSteps: Int?, action: HeadphoneSessionRecoveryAnalyticsEvent.ResumeAction) {
        guard let notice = resumeNotice else { return }
        resumeNotice = nil

        var source = HeadphoneSessionResumeNotice.GapSource.wallClock
        var deltaSteps = 0
        let correctedSteps = machineSteps.map {
            notice.correctedSteps(enteredSteps: $0, sensorStepsNow: motionSession.stepCount)
        }
        if let machineSteps, let correctedSteps, correctedSteps != motionSession.stepCount,
           let correction = motionSession.applyStepCorrection(
               correctedSteps: correctedSteps,
               trackingGapDuration: notice.gap
           ) {
            _ = stepTimelineRecorder.recordCorrection(correction)
            deltaSteps = correction.deltaSteps
            source = machineSteps == notice.suggestedSteps && notice.phoneEstimateSteps ?? 0 > 0
                ? .pedometer
                : .machine
            checkpointer.checkpoint(makeCheckpointSnapshot(), force: true)
        }

        TelemetryManager.shared.track(
            HeadphoneSessionRecoveryAnalyticsEvent.sessionResumed(
                mode: .routine,
                gapSeconds: Int(notice.gap.rounded(.down)),
                gapCreditedSeconds: Int(notice.creditedGap.rounded(.down)),
                lossReason: notice.lossReason,
                source: source,
                deltaSteps: deltaSteps,
                action: action
            )
        )
    }

    /// The phone's own count across the gap arrived after the session started; offer it.
    func attachPhoneStepEstimate(_ steps: Int) {
        guard var notice = resumeNotice else { return }
        notice.phoneEstimateSteps = steps
        resumeNotice = notice
    }

    private func updateCountdown(at now: Date, elapsed forcedElapsed: TimeInterval? = nil) {
        guard let startDate = countdownStartDate else {
            countdownStartDate = now
            return
        }

        let elapsed = forcedElapsed ?? now.timeIntervalSince(startDate)
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
                cancelPreparedBackgroundSession()
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
        checkpointer.checkpoint(makeCheckpointSnapshot())
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
            let draft = try checkpointer.prepareDraftIfNeeded(modelContext: modelContext) {
                makeDraft(startedAt: startedAt)
            }
            try motionSession.startRecording(targetStepCount: nil, resumeState: draft.resumeState)
            if !backgroundSessionService.isRunning {
                backgroundSessionService.start(at: draft.startedAt)
            }
            didPrepareBackgroundSession = false
            recordLiveSplitSample()
            checkpointer.checkpoint(makeCheckpointSnapshot(), force: true)
            ActiveRoutineSessionCoordinator.shared.setActive(self, sessionID: sessionID)
            AppDiagnosticsRecorder.shared.record(
                "routine_headphone_recording_started",
                details: draft.diagnosticDetails
            )
        } catch {
            checkpointer.discardUnstartedDraft(wasRecovered: preexistingDraft != nil)
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

    private func makeDraft(startedAt: Date) -> ActiveHeadphoneWorkoutDraft {
        ActiveHeadphoneWorkoutDraft(
            sessionID: sessionID,
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
            checkpointer.checkpoint(
                makeCheckpointSnapshot(result: result, splitCurve: finalSplitCurve),
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

    private func makeCheckpointSnapshot(
        result: HeadphoneMotionSessionResult? = nil,
        splitCurve: LiveReplaySplitCurve? = nil
    ) -> HeadphoneSessionCheckpointSnapshot {
        HeadphoneSessionCheckpointSnapshot(
            steps: result?.steps ?? currentSteps,
            durationSeconds: result?.duration ?? motionSession.duration,
            sampleCount: result?.sampleCount ?? motionSession.sampleCount,
            splitCurve: splitCurve ?? stepTimelineRecorder.curve,
            trackingIntegrity: result?.trackingIntegrity ?? motionSession.trackingIntegrity,
            stepCorrections: result?.stepCorrections ?? motionSession.stepCorrectionsSnapshot,
            heartRateBuffer: heartRateRecorder.sampleBuffer,
            motionStatus: String(describing: motionSession.status),
            skippedIntervalCount: skippedIntervalCount
        )
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
