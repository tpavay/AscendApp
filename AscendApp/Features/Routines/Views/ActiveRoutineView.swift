import Combine
@preconcurrency import FirebaseAuth
import SwiftData
import SwiftUI

struct ActiveRoutineView: View {
    let routine: Routine

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ModerationStore.self) private var moderationStore
    @State private var viewModel: ActiveRoutineViewModel
    @State private var stepSyncValue = ""

    private let leaderboardTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(routine: Routine, recoveredDraft: ActiveHeadphoneWorkoutDraft? = nil) {
        self.routine = routine
        _viewModel = State(initialValue: ActiveRoutineViewModel(
            routine: routine,
            recoveredDraft: recoveredDraft
        ))
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        // The live leaderboard links to a rival's profile, so this screen owns
        // its navigation stack: it is always presented as a root (full-screen
        // cover or headphone recovery) and never pushed. Session lifecycle stays
        // on the stack so pushing a profile cannot restart the running routine.
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let savedWorkout = viewModel.savedWorkout {
                    routineCompletionSummary(workout: savedWorkout)
                } else {
                    switch viewModel.phase {
                    case .countdown:
                        LiveSessionCountdownOverlay(value: viewModel.countdownValue)
                    case .active, .complete, .finishing, .saving:
                        activeWorkoutView
                    case .failed(let message):
                        failedView(message: message)
                    }

                    if let stepSyncPrompt = viewModel.stepSyncPrompt {
                        stepSyncOverlay(prompt: stepSyncPrompt)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            viewModel.startSession(modelContext: modelContext)
        }
        .keepsScreenAwake(shouldKeepScreenAwake, reason: "Routine session")
        .onDisappear {
            viewModel.stopTimer()
        }
        .onChange(of: viewModel.showCompletionSheet) { _, isShowing in
            if isShowing {
                Task {
                    await saveRoutineForSummary(
                        reason: viewModel.completionStopReason,
                        recordCompletion: viewModel.countsAsCompletion
                    )
                }
            }
        }
        .task(id: viewModel.stepSyncConfirmation?.id) {
            guard viewModel.stepSyncConfirmation != nil else { return }

            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }

            viewModel.dismissStepSyncConfirmation()
        }
        .onChange(of: viewModel.stepSyncPrompt?.id) { _, _ in
            stepSyncValue = viewModel.stepSyncPrompt.map { String($0.detectedSteps) } ?? ""
        }
        .onChange(of: stepSyncValue) { _, newValue in
            let filteredValue = newValue.filter(\.isNumber)
            if filteredValue != newValue {
                stepSyncValue = filteredValue
            }
        }
        .onChange(of: viewModel.phase) { _, phase in
            guard phase == .active else { return }
            Task {
                await viewModel.refreshReplayLeaderboardIfNeeded(force: true)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .inactive || phase == .background else { return }
            viewModel.checkpointForLifecycleChange()
        }
        .onReceive(leaderboardTick) { _ in
            guard viewModel.phase == .active else { return }
            Task {
                await viewModel.refreshReplayLeaderboardIfNeeded()
            }
        }
        .alert("Stop Workout?", isPresented: $bindableViewModel.showStopConfirmation) {
            Button("Continue", role: .cancel) {}
            Button("Save Attempt") {
                bindableViewModel.trackLogWorkoutTapped(surface: .stopAlert)
                Task {
                    await saveRoutineForSummary(reason: .userStopped)
                }
            }
            Button("Discard", role: .destructive) {
                bindableViewModel.trackDiscard(surface: .stopAlert)
                Task {
                    await viewModel.discard(modelContext: modelContext)
                    dismiss()
                }
            }
        } message: {
            Text("Would you like to log your progress before leaving this routine?")
        }
        .trackOnce(screen: .activeRoutine)
    }

    private var activeWorkoutView: some View {
        VStack(spacing: 0) {
            topChrome

            trackingStatusBanner
                .padding(.horizontal, Layout.horizontalPadding)
                .padding(.top, 10)

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

    @ViewBuilder
    private var trackingStatusBanner: some View {
        if let confirmation = viewModel.stepSyncConfirmation {
            trackingBanner(
                iconName: "checkmark.circle.fill",
                message: "Synced with machine. Continuing from \(confirmation.correctedSteps.formatted()) steps.",
                tint: Color.ascendAccent
            )
        } else if viewModel.shouldShowTrackingRecoveryStatus {
            trackingBanner(
                iconName: "airpodspro",
                message: "Headphone tracking paused. Reconnect to keep counting steps.",
                tint: Color.ascendAccent
            )
        }
    }

    private func trackingBanner(iconName: String, message: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)

            Text(message)
                .font(.montserratSemiBold(size: 12))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.09))
        )
        .accessibilityElement(children: .combine)
    }

    private var routineTimeline: some View {
        SegmentedProgressBar(
            intervals: viewModel.intervals,
            elapsedLabel: "\(viewModel.currentSteps.formatted()) steps",
            totalLabel: "\(viewModel.targetStepGoal.formatted()) target",
            elapsedTime: viewModel.timelineElapsed
        )
    }

    private var liveLeaderboardSection: some View {
        LiveReplayLeaderboardPanel(
            rows: moderationStore.moderate(viewModel.leaderboardRows),
            progressScaleSteps: viewModel.leaderboardProgressScale,
            targetStepGoal: viewModel.targetStepGoal,
            progress: viewModel.leaderboardCurrentProgressFraction,
            currentUserPhotoURL: currentUserPhotoURL,
            fetchFailed: viewModel.leaderboardFetchFailed,
            fieldPopulation: viewModel.leaderboardFieldPopulation,
            fieldSize: viewModel.leaderboardFieldSize,
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
        return RoutineIntervalScale.color(of: interval, colorScheme: colorScheme)
    }

    private func routineCompletionSummary(workout: Workout) -> some View {
        let presentation = viewModel.completionSummaryPresentation

        return LiveClimbCompletionSummaryView(
            climb: nil,
            workout: workout,
            leaderboardRank: viewModel.completionLeaderboardRank,
            leaderboardTotal: viewModel.completionLeaderboardTotal,
            leaderboardRankBasis: .liveSession,
            leaderboardContext: viewModel.completionLeaderboardContext,
            moment: .freshCompletion,
            rankingLabelOverride: "ROUTINE RANK",
            completedDetailOverride: "ROUTINE COMPLETE",
            ranksOnLeaderboard: presentation.ranksOnLeaderboard,
            achievementTitleOverride: presentation.achievementTitleOverride,
            achievementIconNameOverride: presentation.achievementIconNameOverride,
            onDone: { _ in
                dismiss()
            }
        )
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "airpodspro")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Color.ascendAccent)

            VStack(spacing: 8) {
                Text("Tracking stopped")
                    .font(.montserratBold(size: 26))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.montserratMedium(size: 15))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                dismiss()
            } label: {
                Text("Close")
                    .font(.montserratBold(size: 15))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.ascendAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 420)
    }

    private func stepSyncOverlay(prompt: RoutineStepSyncPrompt) -> some View {
        ZStack {
            Color.black
                .opacity(0.58)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("We detected a gap.")
                            .font(.montserratBold(size: 24))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Enter the step count currently showing on your stair stepper.")
                            .font(.montserratMedium(size: 14))
                            .foregroundStyle(.white.opacity(0.68))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        TextField("0", text: $stepSyncValue)
                            .keyboardType(.numberPad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.montserratBold(size: 34))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Text("steps")
                            .font(.montserratSemiBold(size: 14))
                            .foregroundStyle(.white.opacity(0.52))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 72)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.14), lineWidth: 1)
                    )
                    .accessibilityLabel("Current machine steps")

                    VStack(spacing: 10) {
                        Button {
                            guard let steps = stepSyncInputSteps else { return }
                            viewModel.syncCurrentMachineSteps(steps)
                        } label: {
                            Text("Sync Current")
                                .font(.montserratBold(size: 15))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(
                                    Capsule()
                                        .fill(Color.ascendAccent)
                                )
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(stepSyncInputSteps == nil)
                        .opacity(stepSyncInputSteps == nil ? 0.55 : 1)

                        Button {
                            viewModel.skipStepSyncPrompt()
                        } label: {
                            Text("Skip")
                                .font(.montserratBold(size: 14))
                                .foregroundStyle(.white.opacity(0.78))
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                                .background(
                                    Capsule()
                                        .fill(.white.opacity(0.10))
                                )
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(22)
                .frame(maxWidth: 352)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(red: 0.07, green: 0.07, blue: 0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.42), radius: 22, x: 0, y: 14)
            }
            .padding(.horizontal, 22)
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint("Ascend tracked \(prompt.detectedSteps) steps before the gap.")
    }

    private var stepSyncInputSteps: Int? {
        Int(stepSyncValue)
    }

    private var shouldKeepScreenAwake: Bool {
        switch viewModel.phase {
        case .countdown, .active:
            return true
        case .finishing, .saving:
            return true
        case .complete, .failed(_):
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
        try? RoutineService(modelContext: modelContext).recordCompletion(for: routine)
        viewModel.markCompletionRecorded()
    }

    private func saveRoutineForSummary(
        reason: HeadphoneMotionSessionStopReason,
        recordCompletion: Bool = false
    ) async {
        do {
            _ = try await viewModel.saveRecordedWorkout(
                modelContext: modelContext,
                reason: reason
            )
            if recordCompletion {
                recordCompletionIfNeeded()
            }
            viewModel.showCompletionSheet = false
        } catch {
            viewModel.showCompletionSheet = false
            viewModel.errorMessage = error.localizedDescription
            viewModel.phase = .failed(error.localizedDescription)
        }
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
        .environment(ModerationStore.shared)
}
