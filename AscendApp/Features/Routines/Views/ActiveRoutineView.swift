import SwiftUI
import SwiftData

struct ActiveRoutineView: View {
    let routine: Routine

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // All state is local to avoid concurrency issues
    @State private var phase: WorkoutPhase = .countdown
    @State private var countdownValue = 3
    @State private var currentIntervalIndex = 0
    @State private var elapsedInInterval: TimeInterval = 0
    @State private var totalElapsed: TimeInterval = 0
    @State private var isPaused = false
    @State private var showStopConfirmation = false
    @State private var showCompletionSheet = false
    @State private var showWorkoutForm = false
    @State private var completedWorkout: Workout?
    @State private var shouldDismissAfterForm = false

    // Timer
    @State private var timerTask: Task<Void, Never>?

    // Cache intervals to avoid repeated JSON decoding
    @State private var cachedIntervals: [RoutineInterval] = []
    @State private var cachedTotalDuration: TimeInterval = 0

    private var currentInterval: RoutineInterval? {
        guard currentIntervalIndex < cachedIntervals.count else { return nil }
        return cachedIntervals[currentIntervalIndex]
    }

    private var nextInterval: RoutineInterval? {
        let nextIndex = currentIntervalIndex + 1
        guard nextIndex < cachedIntervals.count else { return nil }
        return cachedIntervals[nextIndex]
    }

    private var remainingInInterval: TimeInterval {
        guard let interval = currentInterval else { return 0 }
        return max(0, interval.duration - elapsedInInterval)
    }

    private var totalRemaining: TimeInterval {
        max(0, cachedTotalDuration - totalElapsed)
    }

    private var progress: Double {
        guard cachedTotalDuration > 0 else { return 0 }
        return min(1.0, totalElapsed / cachedTotalDuration)
    }

    private var isNearIntervalEnd: Bool {
        remainingInInterval <= 5 && remainingInInterval > 0
    }

    var body: some View {
        ZStack {
            Color.jet.ignoresSafeArea()

            switch phase {
            case .countdown:
                CountdownOverlay(value: countdownValue)
            case .active:
                workoutView
            case .complete:
                Color.clear // Completion sheet will show
            }
        }
        .onAppear {
            // Cache intervals once to avoid repeated JSON decoding during timer ticks
            cachedIntervals = routine.intervals
            cachedTotalDuration = routine.totalDuration
            startCountdown()
        }
        .onDisappear {
            stopTimer()
        }
        .alert("Stop Workout?", isPresented: $showStopConfirmation) {
            Button("Continue", role: .cancel) {}
            Button("Save & Log Workout") {
                stopTimer()
                recordCompletion()
                shouldDismissAfterForm = true
                showWorkoutForm = true
            }
            Button("Discard", role: .destructive) {
                stopTimer()
                dismiss()
            }
        } message: {
            Text("Would you like to log your progress before stopping?")
        }
        .sheet(isPresented: $showCompletionSheet) {
            completionSheet
        }
        .sheet(isPresented: $showWorkoutForm, onDismiss: {
            // After workout form is dismissed (saved or cancelled), dismiss the routine view
            if shouldDismissAfterForm {
                dismiss()
            }
        }) {
            workoutFormSheet
        }
    }

    // MARK: - Countdown

    private func startCountdown() {
        phase = .countdown
        countdownValue = 3

        timerTask = Task { @MainActor in
            for i in [3, 2, 1] {
                guard !Task.isCancelled else { return }
                countdownValue = i
                HapticsManager.shared.trigger(.mediumImpact)
                try? await Task.sleep(for: .seconds(1))
            }

            guard !Task.isCancelled else { return }
            phase = .active
            startTimer()
        }
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()

        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))

                guard !Task.isCancelled, !isPaused else { continue }

                await MainActor.run {
                    tick()
                }
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func tick() {
        guard let interval = currentInterval else { return }

        elapsedInInterval += 0.1
        totalElapsed += 0.1

        // Check if interval is complete
        if elapsedInInterval >= interval.duration {
            advanceToNextInterval()
        }
    }

    private func advanceToNextInterval() {
        elapsedInInterval = 0
        currentIntervalIndex += 1

        if currentIntervalIndex >= cachedIntervals.count {
            completeWorkout()
        } else {
            HapticsManager.shared.trigger(.mediumImpact)
        }
    }

    private func skipInterval() {
        guard let interval = currentInterval else { return }

        let remaining = interval.duration - elapsedInInterval
        totalElapsed += remaining
        elapsedInInterval = 0
        currentIntervalIndex += 1

        if currentIntervalIndex >= cachedIntervals.count {
            completeWorkout()
        } else {
            HapticsManager.shared.trigger(.mediumImpact)
        }
    }

    private func completeWorkout() {
        stopTimer()
        phase = .complete
        HapticsManager.shared.trigger(.success)
        showCompletionSheet = true
    }

    // MARK: - Workout View

    private var workoutView: some View {
        VStack(spacing: 0) {
            TopProgressBar(
                elapsed: formatTime(totalElapsed),
                remaining: formatTime(totalRemaining),
                progress: progress
            )

            Spacer()

            if let interval = currentInterval {
                mainContent(for: interval)
            }

            Spacer()

            controlButtons
        }
    }

    private func mainContent(for interval: RoutineInterval) -> some View {
        VStack(spacing: 24) {
            Text("\(currentIntervalIndex + 1) of \(cachedIntervals.count)")
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.white.opacity(0.5))

            IntervalTimerDisplay(
                intensity: interval.intensityDisplay,
                remainingTime: formatTime(remainingInInterval),
                isNearEnd: isNearIntervalEnd
            )

            ModifierBadges(modifiers: interval.modifiers)

            NextIntervalPreview(interval: nextInterval)
                .padding(.top, 8)
        }
        .padding(.horizontal, 20)
    }

    private var controlButtons: some View {
        HStack(spacing: 24) {
            Button {
                showStopConfirmation = true
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 24, weight: .medium))
                    Text("Stop")
                        .font(.montserratMedium(size: 12))
                }
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 70, height: 70)
                .background(Circle().fill(.white.opacity(0.1)))
            }

            Button {
                isPaused.toggle()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 28, weight: .medium))
                    Text(isPaused ? "Resume" : "Pause")
                        .font(.montserratMedium(size: 12))
                }
                .foregroundStyle(.white)
                .frame(width: 90, height: 90)
                .background(Circle().fill(.accent))
            }

            Button {
                skipInterval()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 24, weight: .medium))
                    Text("Skip")
                        .font(.montserratMedium(size: 12))
                }
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 70, height: 70)
                .background(Circle().fill(.white.opacity(0.1)))
            }
        }
        .padding(.bottom, 40)
    }

    // MARK: - Completion Sheet

    private var completionSheet: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80, weight: .light))
                    .foregroundStyle(.accent)
                    .padding(.top, 20)

                VStack(spacing: 8) {
                    Text("Workout Complete!")
                        .font(.montserratBold(size: 28))
                        .foregroundStyle(.white)

                    Text(routine.name)
                        .font(.montserratMedium(size: 18))
                        .foregroundStyle(.white.opacity(0.7))
                }

                HStack(spacing: 32) {
                    VStack(spacing: 4) {
                        Text(formatDuration(totalElapsed))
                            .font(.montserratBold(size: 28))
                            .foregroundStyle(.white)
                        Text("Duration")
                            .font(.montserratRegular(size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    VStack(spacing: 4) {
                        Text("\(cachedIntervals.count)")
                            .font(.montserratBold(size: 28))
                            .foregroundStyle(.white)
                        Text("Intervals")
                            .font(.montserratRegular(size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white.opacity(0.05))
                )

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        recordCompletion()
                        showCompletionSheet = false
                        shouldDismissAfterForm = true
                        showWorkoutForm = true
                    } label: {
                        Text("Log Workout")
                            .font(.montserratSemiBold(size: 16))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(RoundedRectangle(cornerRadius: 12).fill(.accent))
                    }

                    Button {
                        recordCompletion()
                        dismiss()
                    } label: {
                        Text("Skip")
                            .font(.montserratMedium(size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Color.jet)
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Workout Form Sheet

    private var workoutFormSheet: some View {
        WorkoutFormView(
            showingWorkoutForm: $showWorkoutForm,
            onWorkoutCompleted: { workout in
                completedWorkout = workout
            },
            routinePrefill: RoutinePrefillData(
                name: routine.name,
                duration: totalElapsed,
                weightConfiguration: routine.defaultWeightConfiguration,
                difficulty: routine.difficulty
            )
        )
    }

    // MARK: - Record Completion

    private func recordCompletion() {
        routine.completionCount += 1
        routine.lastCompletedAt = Date()
        try? modelContext.save()
    }

    // MARK: - Helpers

    private func formatTime(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

enum WorkoutPhase {
    case countdown
    case active
    case complete
}

#Preview {
    ActiveRoutineView(routine: BuiltInRoutines.beginner20Min)
}
