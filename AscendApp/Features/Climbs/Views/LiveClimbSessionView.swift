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
        replacingActiveClimb: Bool = false,
        analyticsEntryPoint: LiveClimbAnalyticsEvent.EntryPoint = .unknown
    ) {
        _viewModel = State(initialValue: LiveClimbSessionViewModel(
            climb: climb,
            replacingActiveClimb: replacingActiveClimb,
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
                    climb: viewModel.climb,
                    workout: savedWorkout,
                    leaderboardRank: viewModel.completionLeaderboardRank,
                    leaderboardTotal: viewModel.completionLeaderboardTotal,
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
            Button {
                if viewModel.isRecording {
                    showingDiscardConfirmation = true
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(.white.opacity(0.09))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isRecording ? "Discard live climb" : "Close")

            ClimbArtworkView(climb: viewModel.climb, variant: .thumb)
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.climb.name)
                    .font(.montserratBold(size: 15))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(viewModel.climb.displayLocation)
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

    private var liveLeaderboardSection: some View {
        LiveReplayLeaderboardPanel(
            rows: viewModel.leaderboardRows,
            targetSteps: viewModel.climb.referenceStepCount,
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
                HStack(spacing: 12) {
                    Button {
                        viewModel.togglePause()
                    } label: {
                        Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white.opacity(0.88))
                            .frame(width: 42, height: 42)
                            .background(
                                Circle()
                                    .fill(.white.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(viewModel.isPaused ? "Resume live climb" : "Pause live climb")

                    liveSessionButton(title: "End attempt") {
                        Task {
                            await viewModel.finishAndSave(
                                modelContext: modelContext,
                                reason: .userStopped
                            )
                        }
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

private struct LiveReplayLeaderboardPanel: View {
    @State private var hasScrolledToInitialCurrentUser = false

    let rows: [LiveReplayLeaderboardRow]
    let targetSteps: Int
    let progress: Double
    let currentUserPhotoURL: URL?
    let fetchFailed: Bool
    let tint: Color
    let effectiveColorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("LEADERBOARD")
                    .font(.montserratBold(size: 14))
                    .tracking(1.1)
                    .foregroundStyle(primaryColor)

                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(targetSteps.formatted())
                        .font(.montserratBold(size: 20))
                        .foregroundStyle(primaryColor)
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Text("STEPS")
                        .font(.montserratBold(size: 13))
                        .tracking(0.8)
                        .foregroundStyle(secondaryColor)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            LiveReplayLeaderboardRowView(
                                row: row,
                                targetSteps: targetSteps,
                                progress: progress,
                                currentUserPhotoURL: currentUserPhotoURL,
                                tint: tint,
                                effectiveColorScheme: effectiveColorScheme
                            )
                            .id(row.id)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    scrollToCurrentUserIfNeeded(using: proxy)
                }
                .onChange(of: currentUserRowID) { _, _ in
                    scrollToCurrentUserIfNeeded(using: proxy)
                }
                .animation(
                    .spring(response: 0.3, dampingFraction: 0.82),
                    value: rows.map(\.id)
                )
            }

            if fetchFailed && rows.count <= 1 {
                Text("Leaderboard unavailable")
                    .font(.montserratSemiBold(size: 11))
                    .foregroundStyle(secondaryColor)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
        }
    }

    private var primaryColor: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var secondaryColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.42) : .black.opacity(0.4)
    }

    private var currentUserRowID: String? {
        rows.first(where: \.isCurrentUser)?.id
    }

    private func scrollToCurrentUserIfNeeded(using proxy: ScrollViewProxy) {
        guard !hasScrolledToInitialCurrentUser,
              let currentUserRowID else {
            return
        }

        hasScrolledToInitialCurrentUser = true

        Task {
            await Task.yield()
            withAnimation(.easeOut(duration: 0.24)) {
                proxy.scrollTo(currentUserRowID, anchor: .center)
            }
        }
    }
}

private struct LiveReplayLeaderboardRowView: View {
    let row: LiveReplayLeaderboardRow
    let targetSteps: Int
    let progress: Double
    let currentUserPhotoURL: URL?
    let tint: Color
    let effectiveColorScheme: ColorScheme

    var body: some View {
        ZStack(alignment: .leading) {
            if row.isCurrentUser {
                progressBackground
            }

            HStack(spacing: 10) {
                Text(rankLabel)
                    .font(.montserratBold(size: 16))
                    .foregroundStyle(row.isCurrentUser ? tint : secondaryColor)
                    .frame(width: 38, alignment: .center)
                    .monospacedDigit()

                avatarView

                Text(row.displayName)
                    .font(.montserratBold(size: 17))
                    .foregroundStyle(primaryColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 0)

                Text(row.stepsAtBucket.formatted())
                    .font(.montserratBold(size: row.isCurrentUser ? 24 : 22))
                    .foregroundStyle(row.isCurrentUser ? tint : primaryColor)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
            }
            .padding(.trailing, 4)
        }
        .frame(height: row.isCurrentUser ? 74 : 70)
        .accessibilityElement(children: .combine)
    }

    private var rankLabel: String {
        row.rank.map(String.init) ?? "--"
    }

    private var rowProgress: Double {
        if row.isCurrentUser {
            return min(max(progress, 0), 1)
        }

        guard targetSteps > 0 else { return 0 }
        return min(max(Double(row.stepsAtBucket) / Double(targetSteps), 0), 1)
    }

    private var progressBackground: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(tint.opacity(effectiveColorScheme == .dark ? 0.12 : 0.14))

                Rectangle()
                    .fill(tint.opacity(effectiveColorScheme == .dark ? 0.34 : 0.24))
                    .frame(width: width * rowProgress)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: rowProgress)
    }

    @ViewBuilder
    private var avatarView: some View {
        if let photoURL = resolvedPhotoURL {
            AsyncImage(
                url: photoURL,
                transaction: Transaction(animation: .easeInOut(duration: 0.2))
            ) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure, .empty:
                    avatarTokenView
                @unknown default:
                    avatarTokenView
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(effectiveColorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.10), lineWidth: 1)
            )
            .id(photoURL)
        } else {
            avatarTokenView
        }
    }

    private var resolvedPhotoURL: URL? {
        row.isCurrentUser ? (row.photoURL ?? currentUserPhotoURL) : row.photoURL
    }

    private var avatarTokenView: some View {
        Text(row.avatarToken)
            .font(.montserratBold(size: 13))
            .foregroundStyle(row.isCurrentUser ? .black : .white)
            .frame(width: 44, height: 44)
            .background(Circle().fill(row.isCurrentUser ? tint : avatarColor))
    }

    private var primaryColor: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var secondaryColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.34) : .black.opacity(0.34)
    }

    private var avatarColor: Color {
        let colors: [Color] = [
            Color(hex: "8C5A36"),
            Color(hex: "C69475"),
            Color(hex: "6E4E33"),
            Color(hex: "A36A42")
        ]
        return colors[Int(row.id.hashValue.magnitude % UInt(colors.count))]
    }
}

#Preview {
    NavigationStack {
        LiveClimbSessionView(climb: .preview)
    }
    .preferredColorScheme(.dark)
}
