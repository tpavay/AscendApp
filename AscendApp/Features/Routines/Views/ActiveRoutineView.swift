import Combine
@preconcurrency import FirebaseAuth
import SwiftData
import SwiftUI

struct ActiveRoutineView: View {
    let routine: Routine

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel: ActiveRoutineViewModel

    private let leaderboardTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(routine: Routine) {
        self.routine = routine
        _viewModel = State(initialValue: ActiveRoutineViewModel(routine: routine))
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.phase {
            case .countdown:
                LiveSessionCountdownOverlay(value: viewModel.countdownValue)
            case .active, .complete:
                activeWorkoutView
            }
        }
        .onAppear {
            viewModel.startSession()
        }
        .keepsScreenAwake(shouldKeepScreenAwake, reason: "Routine session")
        .onDisappear {
            viewModel.stopTimer()
        }
        .onChange(of: viewModel.showCompletionSheet) { _, isShowing in
            if isShowing {
                recordCompletionIfNeeded()
            }
        }
        .onChange(of: viewModel.phase) { _, phase in
            guard phase == .active else { return }
            Task {
                await viewModel.refreshReplayLeaderboardIfNeeded(force: true)
            }
        }
        .onReceive(leaderboardTick) { _ in
            guard viewModel.phase == .active else { return }
            Task {
                await viewModel.refreshReplayLeaderboardIfNeeded()
            }
        }
        .alert("Stop Workout?", isPresented: $bindableViewModel.showStopConfirmation) {
            Button("Continue", role: .cancel) {}
            Button("Log Workout") {
                bindableViewModel.trackLogWorkoutTapped(surface: .stopAlert)
                bindableViewModel.shouldDismissAfterForm = true
                bindableViewModel.showWorkoutForm = true
            }
            Button("Discard", role: .destructive) {
                bindableViewModel.trackDiscard(surface: .stopAlert)
                dismiss()
            }
        } message: {
            Text("Would you like to log your progress before leaving this routine?")
        }
        .sheet(isPresented: $bindableViewModel.showCompletionSheet) {
            completionSheet
        }
        .sheet(isPresented: $bindableViewModel.showWorkoutForm, onDismiss: {
            if viewModel.shouldDismissAfterForm {
                dismiss()
            }
        }) {
            workoutFormSheet
        }
    }

    private var activeWorkoutView: some View {
        VStack(spacing: 0) {
            topChrome

            routineTimeline
                .padding(.horizontal, Layout.horizontalPadding)
                .padding(.top, Layout.timelineTopPadding)

            liveLeaderboardSection
                .frame(maxHeight: .infinity)
                .padding(.horizontal, Layout.leaderboardHorizontalPadding)
                .padding(.top, Layout.leaderboardTopPadding)

            intervalStatusPanel
                .padding(.horizontal, Layout.horizontalPadding)
                .padding(.top, Layout.intervalPanelTopPadding)

            bottomControls
                .padding(.horizontal, Layout.horizontalPadding)
                .padding(.top, Layout.controlsTopPadding)
                .padding(.bottom, Layout.controlBottomPadding)
        }
    }

    private var topChrome: some View {
        HStack(spacing: 12) {
            OnboardingBackButton {
                viewModel.showStopConfirmation = true
            }
            .accessibilityLabel("Stop routine")

            VStack(alignment: .leading, spacing: 3) {
                Text(routine.name)
                    .font(.montserratBold(size: 16))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(viewModel.currentIntervalPositionText)
                    .font(.montserratMedium(size: 11))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(viewModel.formattedElapsed)
                .font(.montserratBold(size: 13))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(.white.opacity(0.10))
                )
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.top, Layout.topChromeTopPadding)
    }

    private var routineTimeline: some View {
        SegmentedProgressBar(
            intervals: viewModel.intervals,
            elapsedLabel: "\(viewModel.estimatedCurrentSteps.formatted()) est steps",
            totalLabel: "\(viewModel.targetStepGoal.formatted()) target",
            elapsedTime: viewModel.timelineElapsed
        )
    }

    private var liveLeaderboardSection: some View {
        LiveReplayLeaderboardPanel(
            rows: viewModel.leaderboardRows,
            progressScaleSteps: viewModel.leaderboardProgressScale,
            targetStepGoal: viewModel.targetStepGoal,
            progress: viewModel.leaderboardCurrentProgressFraction,
            currentUserPhotoURL: currentUserPhotoURL,
            fetchFailed: viewModel.leaderboardFetchFailed,
            tint: currentIntervalColor,
            effectiveColorScheme: .dark
        )
    }

    private var intervalStatusPanel: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.formattedRemainingInInterval)
                    .font(.montserratBold(size: 38))
                    .tracking(-1.4)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .monospacedDigit()
                    .accessibilityLabel("Time remaining")
                    .accessibilityValue(Text(viewModel.formattedRemainingInInterval))

                Text("REMAINING")
                    .font(.montserratBold(size: 10))
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(0.38))
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                Text(viewModel.currentLevelText)
                    .font(.montserratBold(size: 22))
                    .foregroundStyle(currentIntervalColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let stepTypeText = viewModel.currentStepTypeText {
                    Text(stepTypeText)
                        .font(.montserratSemiBold(size: 10))
                        .tracking(0.5)
                        .foregroundStyle(currentIntervalColor.opacity(0.62))
                        .lineLimit(1)
                } else {
                    Text("CURRENT LEVEL")
                        .font(.montserratBold(size: 10))
                        .tracking(1.0)
                        .foregroundStyle(.white.opacity(0.38))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 86)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.jetLighter.opacity(0.62))
        )
    }

    private var bottomControls: some View {
        HStack(spacing: Layout.controlSpacing) {
            LiveWorkoutControlButton(
                systemImage: "forward.fill",
                isPrimary: false,
                accessibilityLabel: "Skip to next interval"
            ) {
                viewModel.skipInterval()
            }

            Spacer(minLength: 0)

            LiveWorkoutControlButton(
                systemImage: viewModel.isPaused ? "play.fill" : "pause.fill",
                isPrimary: true,
                accessibilityLabel: viewModel.isPaused ? "Resume workout" : "Pause workout"
            ) {
                viewModel.togglePause()
            }

            Spacer(minLength: 0)

            LiveWorkoutControlButton(
                systemImage: "stop.fill",
                isPrimary: false,
                accessibilityLabel: "Stop workout"
            ) {
                viewModel.showStopConfirmation = true
            }
        }
    }

    private var currentIntervalColor: Color {
        guard let interval = viewModel.currentInterval else { return .accent }
        return Color.heatMapColor(
            for: interval.intensityTier.heatMapScore,
            colorScheme: colorScheme
        )
    }

    private var completionSheet: some View {
        WorkoutCompleteView(
            routineName: routine.name,
            duration: viewModel.actualElapsed,
            intervalCount: viewModel.intervals.count,
            onLogWorkout: {
                viewModel.trackLogWorkoutTapped(surface: .completionSheet)
                viewModel.showCompletionSheet = false
                viewModel.shouldDismissAfterForm = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    viewModel.showWorkoutForm = true
                }
            },
            onDiscard: {
                viewModel.trackDiscard(surface: .completionSheet)
                dismiss()
            }
        )
    }

    private var workoutFormSheet: some View {
        WorkoutFormView(
            showingWorkoutForm: Binding(
                get: { viewModel.showWorkoutForm },
                set: { viewModel.showWorkoutForm = $0 }
            ),
            onWorkoutCompleted: { workout in
                viewModel.trackWorkoutSaved(workout)
                viewModel.showWorkoutForm = false
            },
            routinePrefill: RoutinePrefillData(
                name: routine.name,
                startedAt: routineWorkoutStartedAt,
                duration: viewModel.actualElapsed,
                weightConfiguration: routine.defaultWeightConfiguration,
                difficulty: routine.difficulty,
                attribution: RoutineWorkoutAttribution(
                    routineId: routine.id,
                    routineSource: routine.source,
                    templateId: routine.templateId
                )
            )
        )
    }

    private var routineWorkoutStartedAt: Date {
        viewModel.sessionStartedAt ?? Date().addingTimeInterval(-max(viewModel.actualElapsed, 0))
    }

    private var shouldKeepScreenAwake: Bool {
        switch viewModel.phase {
        case .countdown, .active:
            return true
        case .complete:
            return false
        }
    }

    private var currentUserPhotoURL: URL? {
        if let cachedURL = UserDataRepository.shared.getCachedProfilePictureURL()
            .flatMap(URL.init(string:)) {
            return cachedURL
        }

        return Auth.auth().currentUser?.photoURL
    }

    private func recordCompletionIfNeeded() {
        guard !viewModel.hasRecordedCompletion else { return }
        routine.completionCount += 1
        routine.lastCompletedAt = Date()
        try? modelContext.save()
        viewModel.markCompletionRecorded()
    }
}

private enum Layout {
    static let horizontalPadding: CGFloat = 20
    static let topChromeTopPadding: CGFloat = 14
    static let timelineTopPadding: CGFloat = 16
    static let leaderboardHorizontalPadding: CGFloat = 18
    static let leaderboardTopPadding: CGFloat = 18
    static let intervalPanelTopPadding: CGFloat = 10
    static let controlsTopPadding: CGFloat = 12
    static let controlSpacing: CGFloat = 18
    static let controlBottomPadding: CGFloat = 18
}

#Preview {
    ActiveRoutineView(routine: BuiltInRoutines.previewTemplates.last!)
}
