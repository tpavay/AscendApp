import SwiftData
import SwiftUI

struct LiveClimbCompletionSummaryView: View {
    let climb: Climb?
    let workout: Workout
    let leaderboardRank: Int?
    let leaderboardTotal: Int?
    let allowsRatingPrompt: Bool
    let leaderboardContext: LiveReplayLeaderboardContext?
    let rankingLabelOverride: String?
    let completedDetailOverride: String?
    let unrankedValueText: String
    let unrankedDetailText: String
    let showsPendingRankingState: Bool
    let onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BestEffortCacheEntry.sortKey) private var bestEffortCacheEntries: [BestEffortCacheEntry]
    @State private var showingShareSheet = false
    @State private var showingRatingEnjoymentPrompt = false
    @State private var resultSyncStore = LiveClimbPublicResultSyncStore.shared
    @State private var completionRankSnapshot: LiveReplayCompletionRankSnapshot?
    @State private var computedCompletionRank: LiveReplayCompletionRank?
    @State private var completionFinisherStatus: LiveReplayFinisherStatus?
    @State private var completionSummary: LiveReplayLeaderboardSummary?
    @State private var isLoadingCompletionRank = false
    @State private var didTrackSummaryViewed = false

    init(
        climb: Climb?,
        workout: Workout,
        leaderboardRank: Int?,
        leaderboardTotal: Int?,
        allowsRatingPrompt: Bool,
        leaderboardContext: LiveReplayLeaderboardContext? = nil,
        rankingLabelOverride: String? = nil,
        completedDetailOverride: String? = nil,
        unrankedValueText: String = "Checking",
        unrankedDetailText: String = "LOOKING FOR YOUR RANK",
        showsPendingRankingState: Bool = true,
        onDone: @escaping () -> Void
    ) {
        self.climb = climb
        self.workout = workout
        self.leaderboardRank = leaderboardRank
        self.leaderboardTotal = leaderboardTotal
        self.allowsRatingPrompt = allowsRatingPrompt
        self.leaderboardContext = leaderboardContext
        self.rankingLabelOverride = rankingLabelOverride
        self.completedDetailOverride = completedDetailOverride
        self.unrankedValueText = unrankedValueText
        self.unrankedDetailText = unrankedDetailText
        self.showsPendingRankingState = showsPendingRankingState
        self.onDone = onDone
    }

    private var paceSplits: [LiveClimbPaceSplit] {
        LiveClimbWorkoutSummaryData.paceSplits(
            for: workout,
            targetSteps: climb?.referenceStepCount ?? max(workout.steps, 1)
        )
    }

    private var primaryBestEffort: RankedBestEffort? {
        BestEffortCacheSnapshot(
            entries: bestEffortCacheEntries,
            workouts: [workout]
        )
        .primaryEffort(for: workout)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 18) {
                    rankingSection
                    primaryStatsGrid
                    achievementCard
                    paceSplitsCard
                    paceTrendCard
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    shareButton
                    doneButton
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(Color.black)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showingShareSheet) {
            ShareComposerView(
                workout: workout,
                climb: climb,
                liveClimbRank: displayedRank,
                liveClimbRankTotal: displayedTotal
            )
        }
        .alert("Enjoying Ascend?", isPresented: $showingRatingEnjoymentPrompt) {
            Button("Yes") {
                handleRatingEnjoymentResponse(.yes)
            }

            Button("No", role: .cancel) {
                handleRatingEnjoymentResponse(.no)
            }
        } message: {
            Text("If Ascend made this climb better, leave a quick rating.")
        }
        .task(id: workout.id) {
            await loadCompletionRank()
            trackSummaryViewedIfNeeded()
        }
    }

    private var header: some View {
        HStack {
            OnboardingBackButton {
                handleDoneTapped(surface: .backButton)
            }
            .accessibilityLabel("Close summary")

            Spacer()

            Text("SUMMARY")
                .font(.montserratBold(size: 12))
                .foregroundStyle(.white)

            Spacer()

            Color.clear
                .frame(width: 42, height: 42)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    private var rankingSection: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text(rankingLabelText)
                    .font(.montserratBold(size: 10))
                    .foregroundStyle(.accent)

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(rankingValueText)
                        .font(.montserratBold(size: rankingValueText.count > 6 ? 28 : 44))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .accent.opacity(0.72)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    if let displayedTotal, displayedTotal > 0, displayedRank != nil {
                        Text("of \(displayedTotal.formatted())")
                            .font(.montserratBold(size: 13))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }

                Text(rankingDetailText)
                    .font(.montserratBold(size: 10))
                    .foregroundStyle(.white.opacity(0.46))
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)

                if publicResultStatus?.canRetry == true {
                    Button {
                        retryRankSync()
                    } label: {
                        Text("Retry sync")
                            .font(.montserratBold(size: 10))
                            .foregroundStyle(.accent)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 1)
                }
            }

            Spacer(minLength: 0)

            if showsRankingStatusColumn {
                VStack(alignment: .trailing, spacing: 5) {
                    Text("STATUS")
                        .font(.montserratBold(size: 8))
                        .foregroundStyle(.white.opacity(0.42))

                    Text(rankingStatusText)
                        .font(.montserratBold(size: 11))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rankingSectionBackground)
    }

    private var primaryStatsGrid: some View {
        HStack(spacing: 10) {
            summaryStatCard(title: "TOTAL STEPS", value: workout.steps.formatted())
            summaryStatCard(title: "DURATION", value: workout.durationFormatted)
            summaryStatCard(title: "AVG SPM", value: averageSPMText)
        }
    }

    private var achievementCard: some View {
        HStack(spacing: 14) {
            achievementIcon

            VStack(alignment: .leading, spacing: 5) {
                Text(achievementTitle)
                    .font(.montserratBold(size: 12))
                    .foregroundStyle(.accent)

                Text(achievementSubtitle)
                    .font(.montserratBold(size: 12))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(summaryCardBackground)
    }

    private var paceSplitsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SPLITS")
                    .font(.montserratBold(size: 19))
                    .foregroundStyle(.white)

                HStack(spacing: 5) {
                    Text("\(paceSplits.count.formatted()) \(paceSplits.count == 1 ? "segment" : "segments")")
                        .foregroundStyle(.white.opacity(0.54))

                    Text("·")
                        .foregroundStyle(.accent)

                    Text("Avg \(averageSPMText) SPM")
                        .foregroundStyle(.white.opacity(0.54))
                }
                .font(.montserratMedium(size: 12))
                .lineLimit(1)
                .minimumScaleFactor(0.74)
            }

            VStack(spacing: 8) {
                ForEach(paceSplits) { split in
                    LiveClimbPaceSplitRow(
                        split: split,
                        minStepsPerMinute: minSplitSPM,
                        maxStepsPerMinute: maxSplitSPM
                    )
                }
            }
        }
    }

    private var paceTrendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("SPM TREND")
                        .font(.montserratBold(size: 16))
                        .foregroundStyle(.white)

                    Text("Pace throughout the climb")
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(.white.opacity(0.54))
                }

                Spacer(minLength: 0)

                if paceTrendDelta != 0 {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(paceTrendDeltaText)
                            .font(.montserratBold(size: 20))
                            .foregroundStyle(.accent)
                            .monospacedDigit()

                        Text("Start to Finish")
                            .font(.montserratMedium(size: 10))
                            .foregroundStyle(.white.opacity(0.54))
                    }
                }
            }

            AscendTrendChart(
                values: paceSplits.map(\.stepsPerMinute),
                highlightsLastPoint: true
            )
            .frame(height: 132)
            .accessibilityHidden(true)
        }
    }

    private var shareButton: some View {
        Button {
            if let climb {
                TelemetryManager.shared.track(
                    LiveClimbAnalyticsEvent.summaryShareTapped(
                        climb: climb,
                        rank: displayedRank,
                        rankTotal: displayedTotal
                    )
                )
            }
            showingShareSheet = true
        } label: {
            Text("SHARE")
                .font(.montserratBold(size: 13))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.accent)
                )
        }
        .buttonStyle(.plain)
    }

    private var doneButton: some View {
        Button {
            handleDoneTapped(surface: .doneButton)
        } label: {
            Text("DONE")
                .font(.montserratBold(size: 12))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
        }
        .buttonStyle(.plain)
    }

    private func summaryStatCard(title: String, value: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.montserratBold(size: 8))
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(value)
                .font(.montserratBold(size: 20))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 70)
        .background(summaryCardBackground)
    }

    private var summaryCardBackground: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color(hex: "17191B"))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(.white.opacity(0.06), lineWidth: 1)
            )
    }

    private var rankingSectionBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: "17191B"),
                        Color(hex: "0D0F10")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .accent.opacity(0.16),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 1)
            )
    }

    private var rankingValueText: String {
        if let displayedRank {
            return displayedRank.ordinalText
        }

        switch publicResultStatus?.phase {
        case .savedOnDevice:
            return "Saved"
        case .syncFailedRetry:
            return "Sync failed"
        case .syncingRanking:
            return "Syncing"
        case .pending, .published, nil:
            return showsPendingRankingState ? "Checking" : unrankedValueText
        }
    }

    private var rankingDetailText: String {
        if isUsingComputedRankFallback {
            return "CURRENT LEADERBOARD RANK"
        }

        if displayedRank != nil {
            return completedDetailOverride ?? (climb == nil ? "WORKOUT COMPLETE" : "LIVE CLIMB COMPLETE")
        }

        switch publicResultStatus?.phase {
        case .savedOnDevice:
            return "RESULT SAVED ON DEVICE"
        case .syncFailedRetry:
            return "SYNC YOUR RESULT TO RANK"
        case .syncingRanking:
            return "SYNCING RANKING"
        case .pending, .published, nil:
            return unrankedDetailText
        }
    }

    private var rankingStatusText: String {
        if isUsingComputedRankFallback {
            return "CURRENT"
        }

        if displayedRank != nil {
            return "COMPLETE"
        }

        switch publicResultStatus?.phase {
        case .savedOnDevice:
            return "SAVED"
        case .syncFailedRetry:
            return "FAILED"
        case .syncingRanking:
            return "SYNCING"
        case .pending, .published, nil:
            return "LOADING"
        }
    }

    private var rankingLabelText: String {
        rankingLabelOverride ?? (climb == nil ? "GLOBAL RANK" : "CLIMB RANK")
    }

    private var showsRankingStatusColumn: Bool {
        displayedRank != nil ||
            publicResultStatus?.phase == .savedOnDevice ||
            publicResultStatus?.phase == .syncFailedRetry ||
            publicResultStatus?.phase == .syncingRanking
    }

    private var averageSPMText: String {
        guard averageSPMValue > 0 else { return "0" }
        return Int(averageSPMValue.rounded()).formatted()
    }

    private var averageSPMValue: Double {
        guard let pace = workout.stepsPerMinute, pace > 0 else { return 0 }
        return pace
    }

    private var achievementIcon: some View {
        Group {
            if let primaryBestEffort {
                AppIcon(token: .bestEffortTrophy, pointSize: 20, weight: .bold)
                    .foregroundStyle(primaryBestEffort.trophyColor)
            } else {
                Image(systemName: achievementIconName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.accent)
            }
        }
        .frame(width: 48, height: 48)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(0.06))
        )
    }

    private var achievementIconName: String {
        "checkmark.seal.fill"
    }

    private var achievementTitle: String {
        if primaryBestEffort != nil {
            return "BEST EFFORT"
        }

        return "CLIMB COMPLETE"
    }

    private var achievementSubtitle: String {
        if let primaryBestEffort {
            return primaryBestEffort.sentence
        }

        return "\(climb?.name ?? "Live Climb") saved to history"
    }

    private var publicResultStatus: LiveClimbPublicResultSyncStatus? {
        resultSyncStore.status(for: workout.id)
    }

    private var displayedRank: Int? {
        if climb == nil {
            return leaderboardRank ??
                completionRankSnapshot?.rank ??
                computedCompletionRank?.rank
        }

        return publicResultStatus?.rankSnapshot?.rank ??
            publicResultStatus?.publishStatus?.rankAtCompletion ??
            completionRankSnapshot?.rank ??
            computedCompletionRank?.rank
    }

    private var displayedTotal: Int? {
        if climb == nil {
            return leaderboardTotal ??
                completionRankSnapshot?.completedCount ??
                computedCompletionRank?.completedCount
        }

        if let snapshotTotal = completionRankSnapshot?.completedCount {
            return snapshotTotal
        }

        if let statusTotal = publicResultStatus?.rankSnapshot?.completedCount ??
            publicResultStatus?.publishStatus?.completedCountAtCompletion {
            return statusTotal
        }

        if let computedTotal = computedCompletionRank?.completedCount {
            return computedTotal
        }

        let total = max(
            completionSummary?.completedCount ?? 0,
            publicResultStatus?.phase == .published ? (leaderboardTotal ?? 0) : 0
        )

        return total > 0 ? total : nil
    }

    private var isUsingComputedRankFallback: Bool {
        computedCompletionRank != nil &&
            publicResultStatus?.rankSnapshot == nil &&
            publicResultStatus?.publishStatus?.rankAtCompletion == nil &&
            completionRankSnapshot == nil
    }

    private var effectiveLeaderboardContext: LiveReplayLeaderboardContext? {
        if let leaderboardContext {
            return leaderboardContext
        }

        guard let climb else { return nil }
        return LiveReplayLeaderboardContext.liveClimb(
            climbId: climb.id,
            targetSteps: climb.referenceStepCount
        )
    }

    private var maxSplitSPM: Double {
        max(paceSplits.map(\.stepsPerMinute).max() ?? 0, 1)
    }

    private var minSplitSPM: Double {
        paceSplits.map(\.stepsPerMinute).min() ?? 0
    }

    private var paceTrendDelta: Int {
        guard let firstSPM = paceSplits.first?.stepsPerMinute,
              let lastSPM = paceSplits.last?.stepsPerMinute else {
            return 0
        }

        return Int((lastSPM - firstSPM).rounded())
    }

    private var paceTrendDeltaText: String {
        paceTrendDelta > 0 ? "+\(paceTrendDelta) SPM" : "\(paceTrendDelta) SPM"
    }

    private func handleDoneTapped(surface: LiveClimbAnalyticsEvent.SummaryDismissSurface) {
        if case .doneButton = surface, shouldShowRatingEnjoymentPrompt {
            showingRatingEnjoymentPrompt = true
            return
        }

        finishDoneTapped(surface: surface)
    }

    private func handleRatingEnjoymentResponse(_ response: AppStoreRatingManager.EnjoymentResponse) {
        AppStoreRatingManager.shared.recordEnjoymentResponse(response)

        if response == .yes {
            AppStoreRatingManager.shared.requestReview()
        }

        finishDoneTapped(surface: .doneButton)
    }

    private var shouldShowRatingEnjoymentPrompt: Bool {
        guard allowsRatingPrompt, climb != nil else { return false }

        return AppStoreRatingManager.shared.shouldAskEnjoymentQuestionAfterFirstLiveClimb(
            completedLiveClimbCount: completedLiveClimbCount
        )
    }

    private var completedLiveClimbCount: Int {
        let completedStatus = ClimbAttemptStatus.completed.rawValue
        let descriptor = FetchDescriptor<ClimbAttempt>(
            predicate: #Predicate<ClimbAttempt> { attempt in
                attempt.statusRawValue == completedStatus
            }
        )

        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private func finishDoneTapped(surface: LiveClimbAnalyticsEvent.SummaryDismissSurface) {
        if let climb {
            TelemetryManager.shared.track(
                LiveClimbAnalyticsEvent.summaryDoneTapped(
                    climb: climb,
                    surface: surface
                )
            )
        }
        onDone()
    }

    private func trackSummaryViewedIfNeeded() {
        guard !didTrackSummaryViewed else { return }
        didTrackSummaryViewed = true
        if let climb {
            TelemetryManager.shared.track(
                LiveClimbAnalyticsEvent.summaryViewed(
                    climb: climb,
                    rank: displayedRank,
                    rankTotal: displayedTotal
                )
            )
        }
    }

    @MainActor
    private func loadCompletionRank() async {
        guard !isLoadingCompletionRank,
              let context = effectiveLeaderboardContext else {
            return
        }

        isLoadingCompletionRank = true
        defer {
            isLoadingCompletionRank = false
        }
        computedCompletionRank = nil

        let workoutId = workout.id.uuidString

        async let fetchedSummary = LiveReplayLeaderboardService.shared.fetchSummary(context: context)
        async let fetchedCompletionRankSnapshot = LiveReplayLeaderboardService.shared.fetchCompletionRankSnapshot(
            context: context,
            workoutId: workoutId
        )
        async let fetchedFinisherStatus = LiveReplayLeaderboardService.shared.fetchCurrentUserFinisherStatus(context: context)

        do {
            completionSummary = try await fetchedSummary
        } catch {
#if DEBUG
            debugLog("Live Climb summary count fetch failed: \(error.localizedDescription)")
#endif
        }

        do {
            completionRankSnapshot = try await fetchedCompletionRankSnapshot
        } catch {
#if DEBUG
            debugLog("Live Climb summary rank snapshot fetch failed: \(error.localizedDescription)")
#endif
        }

        do {
            if let finisherStatus = try await fetchedFinisherStatus {
                completionFinisherStatus = finisherStatus
                if let climb {
                    try? ClimbService.shared.mirrorFinisherStatus(
                        finisherStatus,
                        for: climb,
                        modelContext: modelContext
                    )
                }
            }
        } catch {
#if DEBUG
            debugLog("Live Climb summary finisher fetch failed: \(error.localizedDescription)")
#endif
        }

        if let climb {
            await resultSyncStore.refreshUntilRankPublished(
                workout: workout,
                climb: climb
            )
            if let rankSnapshot = resultSyncStore.status(for: workout.id)?.rankSnapshot {
                completionRankSnapshot = rankSnapshot
                computedCompletionRank = nil
                return
            }
        }

        if displayedRank == nil {
            do {
                computedCompletionRank = try await LiveReplayLeaderboardService.shared.fetchCompletionRank(
                    context: context,
                    completionDurationSeconds: workout.duration
                )
            } catch {
#if DEBUG
                debugLog("Live Climb summary computed rank fallback failed: \(error.localizedDescription)")
#endif
            }
        }
    }

    private func retryRankSync() {
        guard let climb else { return }

        Task { @MainActor in
            await resultSyncStore.retrySync(
                workout: workout,
                climb: climb,
                modelContext: modelContext
            )
            if let rankSnapshot = resultSyncStore.status(for: workout.id)?.rankSnapshot {
                completionRankSnapshot = rankSnapshot
                computedCompletionRank = nil
            }
        }
    }
}

private struct LiveClimbPaceSplitRow: View {
    let split: LiveClimbPaceSplit
    let minStepsPerMinute: Double
    let maxStepsPerMinute: Double

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(split.index + 1)")
                .font(.montserratBold(size: 12))
                .foregroundStyle(.white.opacity(0.44))
                .monospacedDigit()
                .frame(width: 26, alignment: .center)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(timeRangeText)
                        .font(.montserratBold(size: 13))
                        .foregroundStyle(.white)
                        .frame(width: 104, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .monospacedDigit()

                    Text("\(split.steps.formatted()) steps")
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Spacer(minLength: 0)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(split.stepsPerMinute.rounded()).formatted())")
                            .font(.montserratBold(size: 20))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Text("SPM")
                            .font(.montserratBold(size: 8))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(width: 64, alignment: .trailing)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.08))

                        Capsule()
                            .fill(splitBarGradient)
                            .frame(width: max(proxy.size.width * barProgress, 12))
                            .shadow(color: .accent.opacity(0.34), radius: 10, x: 0, y: 0)
                    }
                }
                .frame(height: 10)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(timeRangeText), \(split.steps.formatted()) steps, \(Int(split.stepsPerMinute.rounded()).formatted()) steps per minute")
    }

    private var splitBarGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.accent.opacity(0.42),
                Color.accent.opacity(0.82),
                Color.accent
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var barProgress: Double {
        guard maxStepsPerMinute > minStepsPerMinute else { return 1 }

        let range = maxStepsPerMinute - minStepsPerMinute
        let normalizedValue = min(max((split.stepsPerMinute - minStepsPerMinute) / range, 0), 1)
        return 0.25 + (normalizedValue * 0.75)
    }

    private var timeRangeText: String {
        "\(clockTime(split.startElapsedSeconds))-\(clockTime(split.endElapsedSeconds))"
    }
}

private func clockTime(_ seconds: Int) -> String {
    let totalSeconds = max(seconds, 0)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
        return "\(hours):\(minutes < 10 ? "0" : "")\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
    }

    return "\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
}

private extension Int {
    var ordinalText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

#Preview {
    LiveClimbCompletionSummaryView(
        climb: .preview,
        workout: Workout(
            name: "Empire State Building Live Climb",
            duration: 2_712,
            steps: 2_096,
            floors: 102,
            caloriesBurned: 420,
            source: .headphoneMotion
        ),
        leaderboardRank: 12,
        leaderboardTotal: 2_460,
        allowsRatingPrompt: true,
        onDone: {}
    )
    .modelContainer(for: [Workout.self, ClimbAttempt.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self], inMemory: true)
}
