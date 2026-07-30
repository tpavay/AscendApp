@preconcurrency import FirebaseAuth
import SwiftData
import SwiftUI

struct LiveClimbSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ModerationStore.self) private var moderationStore

    @State private var viewModel: LiveClimbSessionViewModel
    @State private var showingZeroStepEndOptions = false
    @State private var showingProgressEndOptions = false
    @State private var countdownValue = 3
    @State private var hasStartedRecording = false
    @State private var countdownRunID = 0
    @State private var showingHeadphoneRequirement = false
    @State private var showingCompatibleHeadphones = false
    @State private var headphoneMotionService = HeadphoneMotionReadinessService.shared
    @State private var didTrackHeadphoneRequirement = false
    @State private var stepSyncValue = ""
    @State private var selectedTab: LiveClimbSessionTab = .justMe
    @State private var liveActivityControlRegistrationID = UUID().uuidString

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

    init(viewModel: LiveClimbSessionViewModel) {
        _viewModel = State(initialValue: viewModel)
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
                    leaderboardContext: viewModel.replayContext,
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

                if let stepSyncPrompt = viewModel.stepSyncPrompt {
                    stepSyncOverlay(prompt: stepSyncPrompt)
                }

                if showingZeroStepEndOptions || showingProgressEndOptions {
                    endAttemptOverlay
                }
            }
        }
        .preferredColorScheme(.dark)
        .keepsScreenAwake(shouldKeepScreenAwake, reason: "Live climb tracking")
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showingCompatibleHeadphones) {
            CompatibleHeadphonesHelpSheet()
                .appSheetStyle(.fitted())
        }
        .onAppear {
            if viewModel.phase != .idle {
                hasStartedRecording = true
            }
            registerLiveActivityControls()
        }
        .onDisappear {
            LiveClimbActivityCommandCenter.shared.unregister(
                sessionID: viewModel.liveActivitySessionID,
                registrationID: liveActivityControlRegistrationID
            )
        }
        .task(id: countdownRunID) {
            await runCountdownThenStart()
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
        .onChange(of: viewModel.motionSession.targetReached) { _, reached in
            guard reached, hasStartedRecording else { return }
            Task {
                await finishIfStepsRecorded(reason: .targetReached)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .inactive || phase == .background else { return }
            viewModel.checkpointForLifecycleChange(modelContext: modelContext)
        }
        .onReceive(liveTick) { _ in
            guard hasStartedRecording, viewModel.isActivelyRecording else { return }
            viewModel.recordLiveSplitSample(modelContext: modelContext)
            viewModel.evaluateStepSyncPrompt()
            if viewModel.durationGoalReached {
                Task {
                    await finishIfStepsRecorded(reason: .targetReached)
                }
                return
            }
            Task {
                await viewModel.refreshReplayLeaderboardIfNeeded()
                await viewModel.updateLiveActivity()
            }
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

    private var shouldKeepScreenAwake: Bool {
        guard !showingHeadphoneRequirement else { return false }

        switch viewModel.phase {
        case .idle, .recording, .saving:
            return true
        case .saved, .failed:
            return false
        }
    }

    private var topChrome: some View {
        HStack(spacing: 10) {
            if !hasStartedRecording {
                OnboardingBackButton {
                    dismiss()
                }
                .accessibilityLabel("Close")
            }

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

            if let heartRateStatus = viewModel.liveHeartRateStatus {
                LiveHeartRateStatusChip(status: heartRateStatus)
            }

            if !(viewModel.isRecording && selectedTab == .justMe) {
                Text(viewModel.elapsedClock)
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
        VStack(spacing: 14) {
            if viewModel.isRecording {
                LiveClimbSessionTabBar(selection: $selectedTab)
            }

            Group {
                if viewModel.isRecording && selectedTab == .justMe {
                    LiveClimbJustMeView(viewModel: viewModel)
                } else {
                    leaderboardPanel
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var leaderboardPanel: some View {
        LiveReplayLeaderboardPanel(
            rows: moderationStore.moderate(viewModel.leaderboardRows),
            progressScaleSteps: viewModel.leaderboardProgressScale,
            targetStepGoal: viewModel.mode.targetStepCount,
            progress: viewModel.leaderboardCurrentProgressFraction,
            currentUserPhotoURL: currentUserPhotoURL,
            fetchFailed: viewModel.leaderboardFetchFailed,
            tint: .accent,
            effectiveColorScheme: .dark,
            showsFilter: false
        )
    }

    @ViewBuilder
    private var trackingStatusBanner: some View {
        if let confirmation = viewModel.stepSyncConfirmation {
            trackingBanner(
                iconName: "checkmark.circle.fill",
                message: "Synced with machine. Continuing from \(confirmation.correctedSteps.formatted()) steps.",
                tint: .accent
            )
        } else if viewModel.shouldShowTrackingRecoveryStatus {
            trackingBanner(
                iconName: "airpodspro",
                message: "Headphone tracking paused. Reconnect to keep counting steps.",
                tint: .accent
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
                endAttemptButton

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

    private var endAttemptButton: some View {
        liveSessionButton(title: "End attempt") {
            presentEndAttemptOptions()
        }
    }

    private var endAttemptOverlay: some View {
        ZStack {
            Color.black
                .opacity(0.64)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(endAttemptTitle)
                        .font(.montserratBold(size: 24))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(endAttemptMessage)
                        .font(.montserratMedium(size: 15))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    if showingProgressEndOptions {
                        endAttemptOverlayButton(
                            title: "Save progress",
                            style: .primary
                        ) {
                            Task {
                                await finishAndSave(reason: .userStopped)
                            }
                        }
                    }

                    endAttemptOverlayButton(
                        title: "Keep climbing",
                        style: .secondary
                    ) {
                        dismissEndAttemptOptions()
                    }

                    endAttemptOverlayButton(
                        title: "Discard attempt",
                        style: .destructive
                    ) {
                        Task {
                            await discardAndDismiss()
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 350)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(red: 0.07, green: 0.08, blue: 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.accent.opacity(0.26), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.48), radius: 30, x: 0, y: 18)
            .padding(.horizontal, 24)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .zIndex(30)
        .accessibilityElement(children: .contain)
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

    private var stepSyncInputSteps: Int? {
        Int(stepSyncValue)
    }

    private var endAttemptTitle: String {
        if showingZeroStepEndOptions {
            return "No Steps Recorded"
        }

        return viewModel.mode.isLandmarkClimb ? "End Attempt?" : "End Session?"
    }

    private var endAttemptMessage: String {
        if showingZeroStepEndOptions {
            return viewModel.mode.isLandmarkClimb
                ? "No steps have been recorded for this climb. Keep climbing or discard the attempt."
                : "No steps have been recorded for this session. Keep climbing or discard it."
        }

        let steps = viewModel.totalRecordedSteps.formatted()
        return viewModel.mode.isLandmarkClimb
            ? "\(steps) steps recorded. Save this progress or discard the attempt."
            : "\(steps) steps recorded. Save this session or discard it."
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
        LiveClimbActivityCommandCenter.shared.register(
            sessionID: viewModel.liveActivitySessionID,
            registrationID: liveActivityControlRegistrationID
        ) { command in
            await handleLiveActivityCommand(command)
        }
    }

    private func handleLiveActivityCommand(_ command: LiveClimbActivityCommand) async {
        switch command {
        case .stop:
            await finishIfStepsRecorded(reason: .userStopped)
        }
    }

    private func presentEndAttemptOptions() {
        withAnimation(.smooth(duration: 0.18)) {
            if viewModel.totalRecordedSteps > 0 {
                showingProgressEndOptions = true
            } else {
                showingZeroStepEndOptions = true
            }
        }
    }

    private func finishIfStepsRecorded(reason: HeadphoneMotionSessionStopReason) async {
        guard viewModel.totalRecordedSteps > 0 else {
            return
        }

        await finishAndSave(reason: reason)
    }

    private func finishAndSave(reason: HeadphoneMotionSessionStopReason) async {
        dismissEndAttemptOptions(animated: false)
        await viewModel.finishAndSave(
            modelContext: modelContext,
            reason: reason
        )
    }

    private func discardAndDismiss() async {
        dismissEndAttemptOptions(animated: false)
        await viewModel.discard(modelContext: modelContext)
        dismiss()
    }

    private func dismissEndAttemptOptions(animated: Bool = true) {
        let updates = {
            showingZeroStepEndOptions = false
            showingProgressEndOptions = false
        }

        if animated {
            withAnimation(.smooth(duration: 0.16), updates)
        } else {
            updates()
        }
    }

    private func endAttemptOverlayButton(
        title: String,
        style: EndAttemptOverlayButtonStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.montserratBold(size: 15))
                .foregroundStyle(style.foregroundStyle)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    Capsule()
                        .fill(style.backgroundStyle)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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
                ? "Ascend counts your steps from motion sensors in your AirPods or Beats. An Apple Watch or phone won't track a climb. Connect a compatible pair to start this live climb."
                : "Ascend counts your steps from motion sensors in your AirPods or Beats. An Apple Watch or phone won't track a session. Connect a compatible pair to start climbing.",
            primaryTitle: "Try Again",
            primaryAction: retryHeadphoneCountdown,
            secondaryTitle: "Close",
            secondaryAction: { dismiss() },
            tertiaryTitle: "See compatible headphones",
            tertiaryAction: presentCompatibleHeadphones
        )
    }

    private func presentCompatibleHeadphones() {
        TelemetryManager.shared.track(
            LiveClimbAnalyticsEvent.headphoneHelpOpened(
                climb: viewModel.mode.climb,
                entryPoint: viewModel.analyticsEntryPoint,
                surface: .sessionGate
            )
        )
        showingCompatibleHeadphones = true
    }

    private func stepSyncOverlay(prompt: LiveStepSyncPrompt) -> some View {
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
                        liveSessionButton(title: "Sync Current") {
                            guard let steps = stepSyncInputSteps else { return }
                            viewModel.syncCurrentMachineSteps(steps)
                        }
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

    private func liveClimbFullScreenOverlay(
        iconName: String,
        title: String,
        message: String,
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String,
        secondaryAction: @escaping () -> Void,
        tertiaryTitle: String? = nil,
        tertiaryAction: (() -> Void)? = nil
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

                    if let tertiaryTitle, let tertiaryAction {
                        Button(action: tertiaryAction) {
                            Text(tertiaryTitle)
                                .font(.montserratSemiBold(size: 13))
                                .foregroundStyle(.accent)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
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
    .environment(ModerationStore.shared)
    .preferredColorScheme(.dark)
}
