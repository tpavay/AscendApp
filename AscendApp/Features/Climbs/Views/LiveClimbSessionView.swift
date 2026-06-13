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
    @State private var countdownRunID = 0
    @State private var showingHeadphoneRequirement = false
    @State private var headphoneMotionService = HeadphoneMotionReadinessService.shared
    @State private var didTrackHeadphoneRequirement = false

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

    init(
        justClimbGoal: JustClimbGoal,
        analyticsEntryPoint: LiveClimbAnalyticsEvent.EntryPoint = .unknown
    ) {
        _viewModel = State(initialValue: LiveClimbSessionViewModel(
            justClimbGoal: justClimbGoal,
            analyticsEntryPoint: analyticsEntryPoint
        ))
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if let savedWorkout = viewModel.savedWorkout,
               viewModel.shouldShowRankedCompletionSummary {
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

                if showingHeadphoneRequirement {
                    headphoneRequiredOverlay
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
        .task(id: countdownRunID) {
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
            if viewModel.durationGoalReached {
                Task {
                    await viewModel.finishAndSave(
                        modelContext: modelContext,
                        reason: .targetReached
                    )
                }
                return
            }
            Task {
                await viewModel.refreshReplayLeaderboardIfNeeded()
                await viewModel.updateLiveActivity()
            }
        }
        .confirmationDialog(
            discardConfirmationTitle,
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

            trackingStatusBanner
                .padding(.horizontal, 20)
                .padding(.top, 10)

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

    private var discardConfirmationTitle: String {
        viewModel.mode.isLandmarkClimb ? "Discard Live Climb?" : "Discard Just Climb?"
    }

    private var discardAccessibilityLabel: String {
        viewModel.mode.isLandmarkClimb ? "Discard live climb" : "Discard Just Climb"
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
            .accessibilityLabel(viewModel.isRecording ? discardAccessibilityLabel : "Close")

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
        if let climb = viewModel.mode.climb {
            ClimbArtworkView(climb: climb, variant: .thumb)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accent)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.black)
                }
        }
    }

    private var liveLeaderboardSection: some View {
        LiveReplayLeaderboardPanel(
            rows: viewModel.leaderboardRows,
            progressScaleSteps: viewModel.leaderboardProgressScale,
            targetStepGoal: viewModel.mode.targetStepCount,
            progress: viewModel.leaderboardCurrentProgressFraction,
            currentUserPhotoURL: currentUserPhotoURL,
            fetchFailed: viewModel.leaderboardFetchFailed,
            tint: .accent,
            effectiveColorScheme: .dark
        )
    }

    @ViewBuilder
    private var trackingStatusBanner: some View {
        if viewModel.shouldShowTrackingRecoveryStatus {
            trackingBanner(
                iconName: "airpodspro",
                message: "Headphone tracking paused. Reconnect to keep counting steps."
            )
        }
    }

    private func trackingBanner(iconName: String, message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.accent)

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
        guard !hasStartedRecording,
              viewModel.phase == .idle else { return }

        countdownValue = 3
        headphoneMotionService.refresh()
        guard headphoneMotionService.readiness.canStartLiveClimb else {
            showHeadphoneRequirement()
            return
        }

        showingHeadphoneRequirement = false

        for value in stride(from: 3, through: 1, by: -1) {
            headphoneMotionService.refresh()
            guard headphoneMotionService.readiness.canStartLiveClimb else {
                showHeadphoneRequirement()
                return
            }

            countdownValue = value
            HapticsManager.shared.trigger(value == 1 ? .heavyImpact : .mediumImpact)

            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }

            headphoneMotionService.refresh()
            guard headphoneMotionService.readiness.canStartLiveClimb else {
                showHeadphoneRequirement()
                return
            }
        }

        headphoneMotionService.refresh()
        guard headphoneMotionService.readiness.canStartLiveClimb else {
            showHeadphoneRequirement()
            return
        }

        hasStartedRecording = true
        viewModel.start(modelContext: modelContext)
        await viewModel.refreshReplayLeaderboardIfNeeded(force: true)
    }

    private func showHeadphoneRequirement() {
        countdownValue = 3
        showingHeadphoneRequirement = true

        guard !didTrackHeadphoneRequirement,
              let climb = viewModel.mode.climb else { return }
        didTrackHeadphoneRequirement = true
        TelemetryManager.shared.track(
            LiveClimbAnalyticsEvent.detailStartBlocked(
                climb: climb,
                entryPoint: viewModel.analyticsEntryPoint,
                reason: .headphonesUnavailable
            )
        )
    }

    private func retryHeadphoneCountdown() {
        headphoneMotionService.refresh()
        guard headphoneMotionService.readiness.canStartLiveClimb else {
            showingHeadphoneRequirement = true
            return
        }

        showingHeadphoneRequirement = false
        didTrackHeadphoneRequirement = false
        countdownValue = 3
        countdownRunID += 1
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
            return viewModel.mode.isLandmarkClimb ? "Climb Complete" : "Session Complete"
        case .failed:
            return "Attempt Saved"
        case .active:
            return "Progress Saved"
        case .abandoned:
            return "Attempt Ended"
        }
    }

    private var headphoneRequiredOverlay: some View {
        liveClimbFullScreenOverlay(
            iconName: "airpodspro",
            title: "Headphones required",
            message: viewModel.mode.isLandmarkClimb
                ? "Connect compatible headphones to start this live climb."
                : "Connect compatible headphones to start climbing.",
            primaryTitle: "Try Again",
            primaryAction: retryHeadphoneCountdown,
            secondaryTitle: "Close",
            secondaryAction: { dismiss() }
        )
    }

    private func liveClimbFullScreenOverlay(
        iconName: String,
        title: String,
        message: String,
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        ZStack {
            Color.black
                .opacity(0.96)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Image(systemName: iconName)
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.accent)
                    .frame(width: 72, height: 72)
                    .background(
                        Circle()
                            .fill(.white.opacity(0.08))
                    )

                VStack(spacing: 10) {
                    Text(title)
                        .font(.montserratBold(size: 28))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.montserratMedium(size: 15))
                        .foregroundStyle(.white.opacity(0.68))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    liveSessionButton(title: primaryTitle, action: primaryAction)

                    Button(action: secondaryAction) {
                        Text(secondaryTitle)
                            .font(.montserratBold(size: 14))
                            .foregroundStyle(.white.opacity(0.82))
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
                .padding(.top, 2)
            }
            .padding(.horizontal, 30)
            .frame(maxWidth: 420)
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    NavigationStack {
        LiveClimbSessionView(climb: .preview)
    }
    .preferredColorScheme(.dark)
}
