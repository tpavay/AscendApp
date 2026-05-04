import Combine
import SwiftData
import SwiftUI

struct ActiveRoutineView: View {
    let routine: Routine

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel: ActiveRoutineViewModel

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
        .onDisappear {
            viewModel.stopTimer()
        }
        .onChange(of: viewModel.showCompletionSheet) { _, isShowing in
            if isShowing {
                recordCompletionIfNeeded()
            }
        }
        .alert("Stop Workout?", isPresented: $bindableViewModel.showStopConfirmation) {
            Button("Continue", role: .cancel) {}
            Button("Log Workout") {
                bindableViewModel.shouldDismissAfterForm = true
                bindableViewModel.showWorkoutForm = true
            }
            Button("Discard", role: .destructive) {
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
        GeometryReader { geometry in
            let bottomPadding = Layout.controlBottomPadding + geometry.safeAreaInsets.bottom
            let staircaseTopPadding = max(
                Layout.minimumStairTopPadding,
                geometry.size.height * Layout.stairTopPaddingRatio
            )
            let staircaseHeight = max(
                geometry.size.height - staircaseTopPadding - bottomPadding - Layout.stairBottomOffset,
                Layout.minimumStairHeight
            )
            let staircaseWidth = min(geometry.size.width * Layout.stairWidthRatio, Layout.maximumStairWidth)

            ZStack {
                StaircaseView(
                    totalSteps: viewModel.staircaseStepCount,
                    currentStepIndex: viewModel.staircaseActiveIndex,
                    isWorkoutComplete: viewModel.phase == .complete
                )
                .frame(width: staircaseWidth, height: staircaseHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, Layout.stairTrailingPadding)
                .padding(.top, staircaseTopPadding)
                .padding(.bottom, bottomPadding + Layout.stairBottomOffset)

                VStack(spacing: 0) {
                    SegmentedProgressBar(
                        title: routine.name,
                        intervals: viewModel.intervals,
                        elapsedLabel: viewModel.formattedElapsed,
                        totalLabel: viewModel.formattedTotalDuration,
                        elapsedTime: viewModel.timelineElapsed
                    )
                    .padding(.horizontal, Layout.horizontalPadding)
                    .padding(.top, Layout.timelineTopPadding)

                    VStack(spacing: 0) {
                        Text(viewModel.formattedRemainingInInterval)
                            .font(.montserratBold(size: Layout.timerFontSize))
                            .tracking(Layout.timerTracking)
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .monospacedDigit()
                            .accessibilityLabel("Time remaining")
                            .accessibilityValue(Text(viewModel.formattedRemainingInInterval))

                        LiveIntervalLevelPill(
                            levelText: viewModel.currentLevelText,
                            stepTypeText: viewModel.currentStepTypeText,
                            color: currentIntervalColor
                        )
                        .padding(.top, Layout.levelPillTopPadding)
                    }
                    .padding(.top, Layout.headerToTimerSpacing)
                    .frame(maxWidth: .infinity)

                    Spacer()
                }

                VStack(spacing: Layout.controlSpacing) {
                    LiveWorkoutControlButton(
                        systemImage: "forward.fill",
                        isPrimary: false,
                        accessibilityLabel: "Skip to next interval"
                    ) {
                        viewModel.skipInterval()
                    }

                    LiveWorkoutControlButton(
                        systemImage: viewModel.isPaused ? "play.fill" : "pause.fill",
                        isPrimary: true,
                        accessibilityLabel: viewModel.isPaused ? "Resume workout" : "Pause workout"
                    ) {
                        viewModel.togglePause()
                    }

                    LiveWorkoutControlButton(
                        systemImage: "stop.fill",
                        isPrimary: false,
                        accessibilityLabel: "Stop workout"
                    ) {
                        viewModel.showStopConfirmation = true
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, Layout.controlLeadingPadding)
                .padding(.bottom, bottomPadding)
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
                viewModel.showCompletionSheet = false
                viewModel.shouldDismissAfterForm = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    viewModel.showWorkoutForm = true
                }
            },
            onDiscard: {
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
            onWorkoutCompleted: { _ in },
            routinePrefill: RoutinePrefillData(
                name: routine.name,
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
    static let timelineTopPadding: CGFloat = 8
    static let headerToTimerSpacing: CGFloat = 40
    static let timerFontSize: CGFloat = 112
    static let timerTracking = -5.0
    static let levelPillTopPadding: CGFloat = 20

    static let controlSpacing: CGFloat = 10
    static let controlLeadingPadding: CGFloat = 24
    static let controlBottomPadding: CGFloat = 34
    static let stairWidthRatio = 0.72
    static let maximumStairWidth: CGFloat = 300
    static let stairTopPaddingRatio = 0.45
    static let minimumStairTopPadding: CGFloat = 340
    static let minimumStairHeight: CGFloat = 320
    static let stairTrailingPadding: CGFloat = 0
    static let stairBottomOffset: CGFloat = 2
}

#Preview {
    ActiveRoutineView(routine: BuiltInRoutines.previewTemplates.last!)
}
