@preconcurrency import FirebaseAuth
import SwiftData
import SwiftUI

struct LiveClimbSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel: LiveClimbSessionViewModel
    @State private var showingDiscardConfirmation = false
    @State private var countdownValue = 3
    @State private var hasStartedRecording = false

    private let liveTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(
        climb: Climb,
        analyticsEntryPoint: LiveClimbAnalyticsEvent.EntryPoint = .unknown
    ) {
        _viewModel = State(initialValue: LiveClimbSessionViewModel(
            climb: climb,
            analyticsEntryPoint: analyticsEntryPoint
        ))
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if let savedWorkout = viewModel.savedWorkout,
               viewModel.phase == .saved(.completed) {
                LiveClimbCompletionSummaryView(
                    climb: viewModel.mode.climb,
                    workout: savedWorkout,
                    leaderboardRank: viewModel.completionLeaderboardRank,
                    leaderboardTotal: viewModel.completionLeaderboardTotal,
                    allowsRatingPrompt: true,
                    onDone: { dismiss() }
                )
            } else {
                sessionContent

                if !hasStartedRecording && viewModel.phase == .idle {
                    LiveSessionCountdownOverlay(value: countdownValue)
                }
            }
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            registerLiveActivityControls()
        }
        .onDisappear {
            LiveClimbActivityCommandCenter.shared.unregister()
        }
        .task {
            await runCountdownThenStart()
        }
        .onChange(of: viewModel.motionSession.targetReached) { _, reached in
            guard reached, hasStartedRecording else { return }
            Task {
                await viewModel.finishAndSave(
                    modelContext: modelContext,
                    reason: .targetReached
                )
            }
        }
        .onReceive(liveTick) { _ in
            guard hasStartedRecording, viewModel.isActivelyRecording else { return }
            viewModel.recordLiveSplitSample()
            Task {
                await viewModel.refreshReplayLeaderboardIfNeeded()
                await viewModel.updateLiveActivity()
            }
        }
        .confirmationDialog(
            "Discard Live Climb?",
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Attempt", role: .destructive) {
                Task {
                    await viewModel.discard(modelContext: modelContext)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(viewModel.discardMessage)
        }
    }

    private var sessionContent: some View {
        VStack(spacing: 0) {
            topChrome

            liveLeaderboardSection
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 18)
                .padding(.top, 12)

            savedSummary
                .padding(.horizontal, 24)
                .padding(.top, 8)

            bottomControls
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 18)
        }
    }

    private var topChrome: some View {
        HStack(spacing: 10) {
            OnboardingBackButton {
                if viewModel.isRecording {
                    showingDiscardConfirmation = true
                } else {
                    dismiss()
                }
            }
            .accessibilityLabel(viewModel.isRecording ? "Discard live climb" : "Close")

            sessionArtwork
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.mode.title)
                    .font(.montserratBold(size: 15))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(viewModel.mode.subtitle)
                    .font(.montserratMedium(size: 11))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(clockTime(viewModel.displayedDuration))
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
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    @ViewBuilder
    private var sessionArtwork: some View {
        ClimbArtworkView(climb: viewModel.mode.climb, variant: .thumb)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var liveLeaderboardSection: some View {
        LiveReplayLeaderboardPanel(
            rows: viewModel.leaderboardRows,
            progressScaleSteps: viewModel.leaderboardProgressScale,
            targetStepGoal: viewModel.mode.targetStepCount,
            progress: viewModel.totalProgressFraction,
            currentUserPhotoURL: currentUserPhotoURL,
            fetchFailed: viewModel.leaderboardFetchFailed,
            tint: .accent,
            effectiveColorScheme: .dark
        )
    }

    @ViewBuilder
    private var savedSummary: some View {
        if case .saved(let status) = viewModel.phase {
            VStack(spacing: 8) {
                Text(savedTitle(for: status))
                    .font(.montserratBold(size: 22))
                    .foregroundStyle(.white)

                if let recordedResult = viewModel.recordedResult {
                    Text("\(recordedResult.steps.formatted()) steps saved")
                        .font(.montserratMedium(size: 15))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)

            switch viewModel.phase {
            case .idle:
                Color.clear
                    .frame(height: 1)

            case .recording:
                liveSessionButton(title: "End attempt") {
                    Task {
                        await viewModel.finishAndSave(
                            modelContext: modelContext,
                            reason: .userStopped
                        )
                    }
                }

            case .saving:
                ProgressView()
                    .tint(.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)

            case .saved:
                liveSessionButton(title: "Done") {
                    dismiss()
                }

            case .failed(let message):
                VStack(spacing: 12) {
                    Text(message)
                        .font(.montserratMedium(size: 15))
                        .foregroundStyle(Color.red.opacity(0.9))
                        .multilineTextAlignment(.center)

                    liveSessionButton(title: "Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func liveSessionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.montserratBold(size: 14))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    Capsule()
                        .fill(Color.accent)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func clockTime(_ interval: TimeInterval) -> String {
        let totalSeconds = max(Int(interval.rounded(.down)), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(minutes < 10 ? "0" : "")\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
        }

        return "\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
    }

    private var currentUserPhotoURL: URL? {
        if let cachedURL = UserDataRepository.shared.getCachedProfilePictureURL()
            .flatMap(URL.init(string:)) {
            return cachedURL
        }

        return Auth.auth().currentUser?.photoURL
    }

    private func runCountdownThenStart() async {
        guard !hasStartedRecording else { return }

        for value in stride(from: 3, through: 1, by: -1) {
            countdownValue = value
            HapticsManager.shared.trigger(value == 1 ? .heavyImpact : .mediumImpact)

            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
        }

        hasStartedRecording = true
        viewModel.start(modelContext: modelContext)
        await viewModel.refreshReplayLeaderboardIfNeeded(force: true)
    }

    private func registerLiveActivityControls() {
        LiveClimbActivityCommandCenter.shared.register { command in
            await handleLiveActivityCommand(command)
        }
    }

    private func handleLiveActivityCommand(_ command: LiveClimbActivityCommand) async {
        switch command {
        case .stop:
            await viewModel.finishAndSave(
                modelContext: modelContext,
                reason: .userStopped
            )
        }
    }

    private func savedTitle(for status: ClimbAttemptStatus) -> String {
        switch status {
        case .completed:
            return "Climb Complete"
        case .failed:
            return "Attempt Saved"
        case .active:
            return "Progress Saved"
        case .abandoned:
            return "Attempt Ended"
        }
    }
}

#Preview {
    NavigationStack {
        LiveClimbSessionView(climb: .preview)
    }
    .preferredColorScheme(.dark)
}
