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
    let motionSession: HeadphoneMotionSessionService
    let analyticsEntryPoint: LiveClimbAnalyticsEvent.EntryPoint

    private let climbService: ClimbService
    private let settingsManager: SettingsManager
    private let leaderboardService: LiveReplayLeaderboardServicing
    private let liveActivityManager: LiveClimbActivityManager
    private let backgroundSessionService: LiveClimbBackgroundSessionService

    private(set) var phase: LiveClimbSessionPhase = .idle
    private(set) var recordedResult: HeadphoneMotionSessionResult?
    private(set) var savedWorkout: Workout?
    private(set) var leaderboardSummary: LiveReplayLeaderboardSummary = .empty
    private(set) var leaderboardWindow: LiveReplayLeaderboardWindow?
    private(set) var leaderboardFetchFailed = false
    private(set) var stepSyncPrompt: LiveStepSyncPrompt?
    private(set) var stepSyncConfirmation: LiveStepSyncConfirmation?

    private var hasSavedSession = false
    private var stepTimelineRecorder: LiveClimbStepTimelineRecorder
    private var isLeaderboardRefreshInFlight = false
    private var lastExhaustedLeaderboardWindowRefreshAt: Date?
    private var lastPeriodicLeaderboardWindowRefreshAt: Date?
    private var promptedStepSyncInterruptionCounts: Set<Int> = []
    private var skippedStepSyncInterruptionCounts: Set<Int> = []
    private let stepSyncPromptMinimumGapDuration: TimeInterval = 20

    init(
        climb: Climb,
        analyticsEntryPoint: LiveClimbAnalyticsEvent.EntryPoint = .unknown,
        motionSession: HeadphoneMotionSessionService = HeadphoneMotionSessionService(),
        climbService: ClimbService = .shared,
        settingsManager: SettingsManager = .shared,
        leaderboardService: LiveReplayLeaderboardServicing = LiveReplayLeaderboardService.shared,
        liveActivityManager: LiveClimbActivityManager = .shared,
        backgroundSessionService: LiveClimbBackgroundSessionService = LiveClimbBackgroundSessionService()
    ) {
        self.mode = .liveClimb(climb)
        self.analyticsEntryPoint = analyticsEntryPoint
        self.motionSession = motionSession
        self.climbService = climbService
        self.settingsManager = settingsManager
        self.leaderboardService = leaderboardService
        self.liveActivityManager = liveActivityManager
        self.backgroundSessionService = backgroundSessionService
        self.stepTimelineRecorder = LiveClimbStepTimelineRecorder(intervalSeconds: 10)
        self.motionSession.setStepSampleHandler { [weak self] sample in
            self?.recordLiveStepSample(sample)
        }
    }

    init(
        justClimbGoal: JustClimbGoal,
        analyticsEntryPoint: LiveClimbAnalyticsEvent.EntryPoint = .unknown,
        motionSession: HeadphoneMotionSessionService = HeadphoneMotionSessionService(),
        climbService: ClimbService = .shared,
        settingsManager: SettingsManager = .shared,
        leaderboardService: LiveReplayLeaderboardServicing = LiveReplayLeaderboardService.shared,
        liveActivityManager: LiveClimbActivityManager = .shared,
        backgroundSessionService: LiveClimbBackgroundSessionService = LiveClimbBackgroundSessionService()
    ) {
        self.mode = .justClimb(justClimbGoal)
        self.analyticsEntryPoint = analyticsEntryPoint
        self.motionSession = motionSession
        self.climbService = climbService
        self.settingsManager = settingsManager
        self.leaderboardService = leaderboardService
        self.liveActivityManager = liveActivityManager
        self.backgroundSessionService = backgroundSessionService
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

        do {
            stepTimelineRecorder.reset()
            stepSyncPrompt = nil
            stepSyncConfirmation = nil
            promptedStepSyncInterruptionCounts.removeAll(keepingCapacity: true)
            skippedStepSyncInterruptionCounts.removeAll(keepingCapacity: true)
            stepTimelineRecorder.record(
                elapsedSeconds: 0,
                cumulativeSteps: 0,
                source: .headphoneMotion
            )
            try motionSession.startRecording(targetStepCount: targetRemainingSteps)
            backgroundSessionService.start()
            phase = .recording
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
            Task { [weak self] in
                await self?.beginLiveActivity()
            }
        } catch {
            phase = .failed(error.localizedDescription)
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
            let workout = try saveWorkout(
                from: result,
                splitCurve: finalSplitCurve,
                modelContext: modelContext
            )
            savedWorkout = workout
            recordedResult = result
            hasSavedSession = true

            let savedStatus = savedAttemptStatus(modelContext: modelContext)
            trackSavedAttempt(result: result, status: savedStatus)
            phase = .saved(savedStatus)
            await liveActivityManager.end(status: .finished)
        } catch {
            phase = .failed(error.localizedDescription)
            await liveActivityManager.end(status: .failed)
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
        backgroundSessionService.stop()

        await liveActivityManager.end(status: .ended)
    }

    func evaluateStepSyncPrompt() {
        guard phase == .recording,
              stepSyncPrompt == nil,
              motionSession.sampleCount > 0 else {
            return
        }

        let trackingIntegrity = motionSession.trackingIntegrity
        guard trackingIntegrity.currentUnavailableDuration >= stepSyncPromptMinimumGapDuration,
              trackingIntegrity.interruptionCount > 0,
              !promptedStepSyncInterruptionCounts.contains(trackingIntegrity.interruptionCount),
              !skippedStepSyncInterruptionCounts.contains(trackingIntegrity.interruptionCount) else {
            return
        }

        promptedStepSyncInterruptionCounts.insert(trackingIntegrity.interruptionCount)
        stepSyncPrompt = LiveStepSyncPrompt(
            detectedSteps: motionSession.stepCount,
            gapDuration: trackingIntegrity.currentUnavailableDuration,
            interruptionCount: trackingIntegrity.interruptionCount
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

    func recordLiveSplitSample() {
        guard phase == .recording,
              motionSession.status.isRecording else { return }

        _ = stepTimelineRecorder.record(
            elapsedSeconds: Int(motionSession.duration.rounded(.down)),
            cumulativeSteps: motionSession.stepCount,
            source: .headphoneMotion
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
                print(
                    "Live replay leaderboard fetched \(replayContext.contextKey) " +
                    "bucket=\(window.bucketIndex) rank=\(window.currentUserRank ?? -1) " +
                    "rows=\(window.rows.count) force=\(forceFreshWindow) " +
                    "steps=\(totalRecordedSteps) duration=\(String(format: "%.2f", duration))s"
                )
#endif
            } else {
#if DEBUG
                print(
                    "Live replay leaderboard skipped \(replayContext.contextKey) " +
                    "force=\(forceFreshWindow) steps=\(totalRecordedSteps)"
                )
#endif
            }

            leaderboardFetchFailed = false
        } catch {
#if DEBUG
            print("Live replay leaderboard fetch failed for \(replayContext.contextKey): \(error.localizedDescription)")
#endif
            leaderboardFetchFailed = true
        }

        await updateLiveActivity(force: force || forceFreshWindow)
    }

    func updateLiveActivity(force: Bool = false) async {
        await updateLiveActivity(status: nil, force: force)
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

    private func saveWorkout(
        from result: HeadphoneMotionSessionResult,
        splitCurve: LiveReplaySplitCurve,
        modelContext: ModelContext
    ) throws -> Workout {
        if let climb = mode.climb {
            _ = try climbService.prepareLiveClimbAttempt(
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

        let workout = Workout(
            name: mode.workoutName,
            date: result.startedAt,
            duration: max(result.duration, 1),
            steps: result.steps,
            floors: floors,
            stepsPerFloor: Workout.defaultStepsPerFloor,
            source: .headphoneMotion,
            deviceModel: UIDevice.current.model,
            sourceMetadata: metadata.jsonString
        )

        modelContext.insert(workout)
        try modelContext.save()

        if mode.isLandmarkClimb {
            try climbService.apply(workouts: [workout], modelContext: modelContext)
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

        return workout
    }

    private func savedAttemptStatus(modelContext: ModelContext) -> ClimbAttemptStatus {
        guard let climb = mode.climb else {
            return .completed
        }

        return climbService
            .historySummary(for: climb, modelContext: modelContext)
            .recentEntries
            .first?
            .status ?? .completed
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
