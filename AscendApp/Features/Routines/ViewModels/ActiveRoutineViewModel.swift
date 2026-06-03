import Combine
import Foundation

@MainActor
@Observable
final class ActiveRoutineViewModel {
    let routine: Routine
    let intervals: [RoutineInterval]
    let totalDuration: TimeInterval

    private let replayContext: LiveReplayLeaderboardContext
    private let leaderboardService: LiveReplayLeaderboardServicing

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
    var showWorkoutForm = false
    var shouldDismissAfterForm = false
    private(set) var leaderboardWindow: LiveReplayLeaderboardWindow?
    private(set) var leaderboardFetchFailed = false

    private var countdownStartDate: Date?
    private var lastTickDate: Date?
    private var lastCountdownHapticValue: Int?
    private var lastWarningSecond: Int?
    @ObservationIgnored private var timerCancellable: AnyCancellable?
    private(set) var hasRecordedCompletion = false

    init(
        routine: Routine,
        leaderboardService: LiveReplayLeaderboardServicing = LiveReplayLeaderboardService.shared
    ) {
        self.routine = routine
        intervals = routine.intervals
        totalDuration = routine.totalDuration
        replayContext = RoutineReplayLeaderboardContextBuilder.context(for: routine)
        self.leaderboardService = leaderboardService
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

    var estimatedCurrentSteps: Int {
        let estimatedSteps = intervals.indices.reduce(0.0) { total, index in
            let interval = intervals[index]
            let intervalElapsed: TimeInterval

            if index < currentIntervalIndex {
                intervalElapsed = interval.duration
            } else if index == currentIntervalIndex {
                intervalElapsed = min(max(elapsedInInterval, 0), interval.duration)
            } else {
                intervalElapsed = 0
            }

            return total + (Double(interval.mappedStepsPerMinute) * intervalElapsed / 60)
        }

        return max(Int(estimatedSteps.rounded()), 0)
    }

    var leaderboardRows: [LiveReplayLeaderboardRow] {
        guard let leaderboardWindow else {
            return [
                LiveReplayLeaderboardRow.currentUser(
                    rank: nil,
                    steps: estimatedCurrentSteps
                )
            ]
        }

        return leaderboardWindow.locallyRankedRows(
            currentSteps: estimatedCurrentSteps,
            currentElapsedSeconds: Int(timelineElapsed.rounded(.down))
        )
    }

    var leaderboardProgressScale: Int {
        let fetchedMaxSteps = leaderboardWindow?.rows.map(\.finalSteps).max() ?? 0
        return max(max(targetStepGoal, fetchedMaxSteps), estimatedCurrentSteps)
    }

    var leaderboardCurrentProgressFraction: Double {
        guard leaderboardProgressScale > 0 else { return 0 }
        return min(max(Double(estimatedCurrentSteps) / Double(leaderboardProgressScale), 0), 1)
    }

    var currentIntervalPositionText: String {
        guard !intervals.isEmpty else { return "No intervals" }
        let displayIndex = min(max(currentIntervalIndex + 1, 1), intervals.count)
        return "Interval \(displayIndex) of \(intervals.count)"
    }

    var isNearIntervalEnd: Bool {
        remainingInInterval <= 3 && remainingInInterval > 0
    }

    func startSession() {
        stopTimer()
        phase = .countdown
        countdownValue = 3
        currentIntervalIndex = 0
        elapsedInInterval = 0
        actualElapsed = 0
        timelineElapsed = 0
        sessionStartedAt = nil
        isPaused = false
        showCompletionSheet = false
        showWorkoutForm = false
        shouldDismissAfterForm = false
        leaderboardWindow = nil
        leaderboardFetchFailed = false
        countdownStartDate = Date()
        lastTickDate = nil
        lastCountdownHapticValue = 3
        lastWarningSecond = nil
        hasRecordedCompletion = false
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
        case .complete:
            break
        }
    }

    func togglePause() {
        isPaused.toggle()
        lastTickDate = nil
        HapticsManager.shared.trigger(.mediumImpact)
    }

    func skipInterval() {
        guard let currentInterval else { return }

        let remainingTimeline = max(currentInterval.duration - elapsedInInterval, 0)
        timelineElapsed += remainingTimeline
        elapsedInInterval = 0
        lastWarningSecond = nil
        currentIntervalIndex += 1
        lastTickDate = Date()

        if currentIntervalIndex >= intervals.count {
            completeWorkout()
        } else {
            HapticsManager.shared.trigger(.heavyImpact)
        }
    }

    func markCompletionRecorded() {
        hasRecordedCompletion = true
    }

    func refreshReplayLeaderboardIfNeeded(force: Bool = false) async {
        guard phase == .active || phase == .complete else { return }

        do {
            let window = try await leaderboardService.refreshIfNeeded(
                context: replayContext,
                elapsedSeconds: Int(timelineElapsed.rounded(.down)),
                currentSteps: estimatedCurrentSteps,
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
            phase = .active
            sessionStartedAt = now
            self.countdownStartDate = nil
            lastTickDate = now
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
        actualElapsed += delta
        timelineElapsed += delta

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
        phase = .complete
        isPaused = false
        lastTickDate = nil
        lastWarningSecond = nil
        showCompletionSheet = true
        HapticsManager.shared.trigger(.success)
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
    case complete
}
