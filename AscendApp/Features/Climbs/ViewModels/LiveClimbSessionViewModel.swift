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
    case activeAttemptMismatch
    case noStepsRecorded

    var errorDescription: String? {
        switch self {
        case .activeAttemptMismatch:
            return "Another climb is currently active."
        case .noStepsRecorded:
            return "No steps were recorded for this attempt."
        }
    }
}

@MainActor
@Observable
final class LiveClimbSessionViewModel {
    let climb: Climb
    let motionSession: HeadphoneMotionSessionService
    let replacingActiveClimb: Bool

    private let climbService: ClimbService
    private let settingsManager: SettingsManager
    private let leaderboardService: LiveReplayLeaderboardServicing

    private(set) var phase: LiveClimbSessionPhase = .idle
    private(set) var baselineSteps = 0
    private(set) var baselineDurationSeconds = 0
    private(set) var baselineSessionsCount = 0
    private(set) var recordedResult: HeadphoneMotionSessionResult?
    private(set) var savedWorkout: Workout?
    private(set) var leaderboardSummary: LiveReplayLeaderboardSummary = .empty
    private(set) var leaderboardWindow: LiveReplayLeaderboardWindow?
    private(set) var leaderboardFetchFailed = false

    private var hasSavedSession = false
    private var continuesPersistedAttempt = false
    private var splitSampler: LiveReplaySplitSampler
    private var isLeaderboardRefreshInFlight = false
    private var lastExhaustedLeaderboardWindowRefreshAt: Date?
    private var lastPeriodicLeaderboardWindowRefreshAt: Date?

    init(
        climb: Climb,
        replacingActiveClimb: Bool = false,
        motionSession: HeadphoneMotionSessionService = HeadphoneMotionSessionService(),
        climbService: ClimbService = .shared,
        settingsManager: SettingsManager = .shared,
        leaderboardService: LiveReplayLeaderboardServicing = LiveReplayLeaderboardService.shared
    ) {
        self.climb = climb
        self.replacingActiveClimb = replacingActiveClimb
        self.motionSession = motionSession
        self.climbService = climbService
        self.settingsManager = settingsManager
        self.leaderboardService = leaderboardService
        self.splitSampler = LiveReplaySplitSampler(intervalSeconds: 10)
    }

    var totalRecordedSteps: Int {
        min(climb.referenceStepCount, baselineSteps + motionSession.stepCount)
    }

    var targetRemainingSteps: Int {
        max(climb.referenceStepCount - baselineSteps, 1)
    }

    var totalProgressFraction: Double {
        guard climb.referenceStepCount > 0 else { return 0 }
        return min(max(Double(totalRecordedSteps) / Double(climb.referenceStepCount), 0), 1)
    }

    var totalProgressPercent: Int {
        Int((totalProgressFraction * 100).rounded())
    }

    var displayedDuration: TimeInterval {
        TimeInterval(baselineDurationSeconds) + motionSession.duration
    }

    var displayedFloors: Int {
        Workout.stepsToFloors(totalRecordedSteps, stepsPerFloor: settingsManager.stepsPerFloor)
    }

    var estimatedDuration: TimeInterval {
        let spm = max(settingsManager.effectiveBaseLevelSPM, 1)
        return (Double(climb.referenceStepCount) / Double(spm)) * 60
    }

    var currentStepsPerMinute: Int {
        guard displayedDuration > 0 else { return 0 }
        return Int((Double(totalRecordedSteps) / (displayedDuration / 60)).rounded())
    }

    var replayContext: LiveReplayLeaderboardContext {
        .liveClimb(
            climbId: climb.id,
            targetSteps: climb.referenceStepCount
        )
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

    var leaderboardTotalClimbers: Int {
        max(leaderboardWindow?.totalClimbers ?? 0, leaderboardSummary.totalClimbers)
    }

    var leaderboardCompletedCount: Int {
        leaderboardSummary.completedCount
    }

    var leaderboardUpdatedElapsedSeconds: Int? {
        leaderboardWindow?.bucketElapsedSeconds
    }

    var isRecording: Bool {
        phase == .recording
    }

    var isActivelyRecording: Bool {
        phase == .recording && motionSession.status.isRecording
    }

    var isPaused: Bool {
        phase == .recording && motionSession.status.isPaused
    }

    var isBusy: Bool {
        phase == .saving
    }

    var discardMessage: String {
        if baselineSessionsCount == 0 && baselineSteps == 0 {
            return "This will stop tracking and discard this new climb attempt."
        }

        return "This will stop the current recording. Your earlier climb progress will stay active."
    }

    func start(modelContext: ModelContext) {
        guard phase == .idle else { return }

        do {
            if let activeAttempt = try climbService.activeAttempt(modelContext: modelContext) {
                if activeAttempt.climbId == climb.id {
                    baselineSteps = activeAttempt.accumulatedSteps
                    baselineDurationSeconds = activeAttempt.accumulatedDurationSeconds
                    baselineSessionsCount = activeAttempt.sessionsCount
                    continuesPersistedAttempt = true
                } else if !replacingActiveClimb {
                    throw LiveClimbSessionError.activeAttemptMismatch
                }
            }

            try motionSession.startRecording(targetStepCount: targetRemainingSteps)
            splitSampler.reset()
            phase = .recording
            recordLiveSplitSample()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func finishAndSave(
        modelContext: ModelContext,
        reason: HeadphoneMotionSessionStopReason
    ) async {
        guard !hasSavedSession,
              phase == .recording || motionSession.status.isRecording || motionSession.status.isPaused else {
            return
        }

        phase = .saving

        do {
            let result = try await motionSession.stopRecording(reason: reason)
            guard result.hasRecordedSteps else {
                throw LiveClimbSessionError.noStepsRecorded
            }

            let finalSplitCurve = splitSampler.record(
                elapsedSeconds: Int(result.duration.rounded(.down)),
                steps: result.steps
            )
            let workout = try saveWorkout(
                from: result,
                splitCurve: finalSplitCurve,
                modelContext: modelContext
            )
            savedWorkout = workout
            recordedResult = result
            hasSavedSession = true

            phase = .saved(savedAttemptStatus(modelContext: modelContext))
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func togglePause() {
        guard phase == .recording else { return }

        do {
            if motionSession.status.isPaused {
                try motionSession.resumeRecording()
            } else {
                try motionSession.pauseRecording()
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func discard(modelContext: ModelContext) async {
        if motionSession.status.isRecording || motionSession.status.isPaused {
            _ = try? await motionSession.stopRecording(reason: .discarded)
        }

        do {
            guard continuesPersistedAttempt && baselineSessionsCount == 0 && baselineSteps == 0 else { return }
            _ = try climbService.abandonActiveClimb(modelContext: modelContext)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func recordLiveSplitSample() {
        guard phase == .recording,
              motionSession.status.isRecording else { return }

        _ = splitSampler.record(
            elapsedSeconds: Int(displayedDuration.rounded(.down)),
            steps: totalRecordedSteps
        )
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

    private func saveWorkout(
        from result: HeadphoneMotionSessionResult,
        splitCurve: LiveReplaySplitCurve,
        modelContext: ModelContext
    ) throws -> Workout {
        _ = try climbService.prepareLiveClimbAttempt(
            for: climb,
            startedAt: result.startedAt,
            replacingActiveClimb: replacingActiveClimb,
            modelContext: modelContext
        )

        let stepsPerFloor = settingsManager.stepsPerFloor
        let floors = Workout.stepsToFloors(result.steps, stepsPerFloor: stepsPerFloor)
        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: result.sampleCount,
            climbId: climb.id,
            targetStepCount: targetRemainingSteps,
            stopReason: result.stopReason,
            splitCurve: splitCurve
        )

        let workout = Workout(
            name: "\(climb.name) Live Climb",
            date: result.startedAt,
            duration: max(result.duration, 1),
            steps: result.steps,
            floors: floors,
            stepsPerFloor: stepsPerFloor,
            source: .headphoneMotion,
            deviceModel: UIDevice.current.model,
            sourceMetadata: metadata.jsonString
        )

        modelContext.insert(workout)
        try modelContext.save()

        try climbService.apply(workouts: [workout], modelContext: modelContext)
        try WorkoutMutationHandler.shared.workoutsDidChange(
            modelContext: modelContext,
            mutation: .created([LeaderboardWorkoutSnapshot(workout: workout)]),
            newWorkouts: [workout],
            changedWorkouts: [workout]
        )

        return workout
    }

    private func savedAttemptStatus(modelContext: ModelContext) -> ClimbAttemptStatus {
        if let activeAttempt = try? climbService.activeAttempt(modelContext: modelContext),
           activeAttempt.climbId == climb.id {
            return .active
        }

        return climbService
            .historySummary(for: climb, modelContext: modelContext)
            .recentEntries
            .first?
            .status ?? .completed
    }
}
