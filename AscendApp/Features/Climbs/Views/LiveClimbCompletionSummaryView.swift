import SwiftData
import SwiftUI

struct LiveClimbCompletionSummaryView: View {
    let climb: Climb?
    let workout: Workout
    let leaderboardRank: Int?
    let leaderboardTotal: Int?
    let leaderboardRankBasis: LiveClimbSummaryRankHero.Basis
    let allowsRatingPrompt: Bool
    let leaderboardContext: LiveReplayLeaderboardContext?
    let moment: LiveClimbSummaryRankHero.Moment
    let rankingLabelOverride: String?
    /// Only reaches the detail line under a `.liveSession` standing, whose race window the
    /// hero cannot characterise. See `LiveClimbSummaryRankHero.Copy`.
    let completedDetailOverride: String?
    let ranksOnLeaderboard: Bool
    let achievementTitleOverride: String?
    let achievementIconNameOverride: String?
    let onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BestEffortCacheEntry.sortKey) private var bestEffortCacheEntries: [BestEffortCacheEntry]
    @State private var showingShareSheet = false
    @State private var showingRatingEnjoymentPrompt = false
    @State private var resultSyncStore = LiveClimbPublicResultSyncStore.shared
    @State private var frozenCompletionRank: LiveReplayCompletionRankSnapshot?
    @State private var computedCompletionRank: LiveReplayCompletionRank?
    @State private var rankResolution: LiveClimbSummaryRankHero.RankResolution = .notStarted
    @State private var didTrackSummaryViewed = false
    @State private var enrichmentService = AppleHealthEnrichmentService.shared
    @State private var isConnectingAppleHealth = false
    @State private var didDismissHeartRateConnect = false
    @State private var appleHealthConnectTask: Task<Void, Never>?

    init(
        climb: Climb?,
        workout: Workout,
        leaderboardRank: Int?,
        leaderboardTotal: Int?,
        leaderboardRankBasis: LiveClimbSummaryRankHero.Basis,
        allowsRatingPrompt: Bool,
        leaderboardContext: LiveReplayLeaderboardContext? = nil,
        moment: LiveClimbSummaryRankHero.Moment = .retrospective,
        rankingLabelOverride: String? = nil,
        completedDetailOverride: String? = nil,
        ranksOnLeaderboard: Bool = true,
        achievementTitleOverride: String? = nil,
        achievementIconNameOverride: String? = nil,
        onDone: @escaping () -> Void
    ) {
        self.climb = climb
        self.workout = workout
        self.leaderboardRank = leaderboardRank
        self.leaderboardTotal = leaderboardTotal
        self.leaderboardRankBasis = leaderboardRankBasis
        self.allowsRatingPrompt = allowsRatingPrompt
        self.leaderboardContext = leaderboardContext
        self.moment = moment
        self.rankingLabelOverride = rankingLabelOverride
        self.completedDetailOverride = completedDetailOverride
        self.ranksOnLeaderboard = ranksOnLeaderboard
        self.achievementTitleOverride = achievementTitleOverride
        self.achievementIconNameOverride = achievementIconNameOverride
        self.onDone = onDone
        self.paceSplits = LiveClimbWorkoutSummaryData.paceSplits(
            for: workout,
            targetSteps: climb?.referenceStepCount ?? max(workout.steps, 1)
        )
    }

    /// Built once per view value. The body reads it eleven times - segment count,
    /// average, each row, the trend chart, the fastest/slowest bounds - and as a
    /// computed property that meant eleven metadata decodes and eleven curve
    /// rebuilds per render pass.
    private let paceSplits: [LiveClimbPaceSplit]

    private var primaryBestEffort: RankedBestEffort? {
        BestEffortCacheSnapshot(
            entries: bestEffortCacheEntries,
            workouts: [workout]
        )
        .primaryEffort(for: workout)
    }

    var body: some View {
        let hero = rankHero

        return VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 18) {
                    rankingSection(hero: hero)
                    primaryStatsGrid
                    heartRateConnectCard
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
                    shareButton(hero: hero)
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
                liveClimbRank: hero?.standing?.rank,
                liveClimbRankTotal: hero?.total
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
            await resolveCompletionRank()
            trackSummaryViewedIfNeeded()
        }
        .onDisappear {
            // Unstructured, so it would otherwise outlive the summary still holding the
            // workout and still writing to state nobody reads.
            appleHealthConnectTask?.cancel()
            appleHealthConnectTask = nil
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

    @ViewBuilder
    private func rankingSection(hero: LiveClimbSummaryRankHero?) -> some View {
        if let hero {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    // The retry button stays outside the combined element: merging it in would
                    // replace its label with the standing and hide the action from VoiceOver.
                    VStack(alignment: .leading, spacing: 7) {
                        Text(hero.label)
                            .font(.montserratBold(size: 10))
                            .foregroundStyle(.accent)

                        rankingValue(for: hero)

                        Text(hero.detail)
                            .font(.montserratBold(size: 10))
                            .foregroundStyle(.white.opacity(0.46))
                            .lineLimit(1)
                            .minimumScaleFactor(0.74)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(rankingAccessibilityLabel(for: hero))

                    if hero.showsRetrySync {
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
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rankingSectionBackground)
        }
    }

    /// The value slot only ever holds a rank or the shared loading treatment - a status word here
    /// reads as a load that never finished, which is the defect this replaced.
    @ViewBuilder
    private func rankingValue(for hero: LiveClimbSummaryRankHero) -> some View {
        switch hero.value {
        case .rank(let rank):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(rank.rankOrdinalText)
                    .font(.montserratBold(size: 44))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .accent.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let total = hero.total {
                    Text("of \(total.formatted())")
                        .font(.montserratBold(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }

        case .loading:
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                AscendSkeletonText(width: 96, height: 40)
                AscendSkeletonText(width: 46, height: 13)
            }

        case .unranked:
            EmptyView()
        }
    }

    private func rankingAccessibilityLabel(for hero: LiveClimbSummaryRankHero) -> String {
        switch hero.value {
        case .rank(let rank):
            let position = hero.total.map { "\(rank.rankOrdinalText) of \($0.formatted())" }
                ?? rank.rankOrdinalText
            return "\(hero.label), \(position), \(hero.detail)"
        case .loading:
            return "\(hero.label), loading"
        case .unranked:
            return "\(hero.label), \(hero.detail)"
        }
    }

    private var primaryStatsGrid: some View {
        HStack(spacing: 10) {
            summaryStatCard(title: "TOTAL STEPS", value: workout.steps.formatted())
            summaryStatCard(title: "DURATION", value: workout.durationFormatted)
            summaryStatCard(title: "AVG SPM", value: averageSPMText)
        }
    }

    /// Offered only to a climber who could actually act on it: this climb has no heart rate
    /// and Apple Health has never been connected. A climber who already connected sees
    /// nothing here - their climb is already in the retry series, and the workout detail is
    /// where its progress is reported.
    @ViewBuilder
    private var heartRateConnectCard: some View {
        if !didDismissHeartRateConnect, enrichmentService.offersConnectionPrompt(for: workout) {
            LiveClimbHeartRateConnectCard(
                isConnecting: isConnectingAppleHealth,
                onConnect: connectAppleHealthForHeartRate,
                onDismiss: { didDismissHeartRateConnect = true }
            )
            .background(summaryCardBackground)
        }
    }

    private func connectAppleHealthForHeartRate() {
        guard !isConnectingAppleHealth else { return }

        appleHealthConnectTask = Task { @MainActor in
            isConnectingAppleHealth = true
            defer { isConnectingAppleHealth = false }

            let result = await enrichmentService.connectAndFetch(
                workout,
                modelContext: modelContext
            )
            HapticsManager.shared.trigger(result == .added ? .success : .warning)

            // Connecting is the whole ask. Whether the samples had landed yet is the retry
            // series' problem now, and repeating the offer would be asking for something the
            // climber already gave.
            if enrichmentService.connectionState == .connected {
                didDismissHeartRateConnect = true
            }
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

    private func shareButton(hero: LiveClimbSummaryRankHero?) -> some View {
        Button {
            if let climb {
                TelemetryManager.shared.track(
                    LiveClimbAnalyticsEvent.summaryShareTapped(
                        climb: climb,
                        rank: hero?.standing?.rank,
                        rankTotal: hero?.total
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
        achievementIconNameOverride ?? "checkmark.seal.fill"
    }

    /// A Best Effort survives the override: it is derived from the steps the climber really took, so
    /// it stands on its own without asserting that the session counted.
    private var achievementTitle: String {
        if primaryBestEffort != nil {
            return "BEST EFFORT"
        }

        return achievementTitleOverride ?? "CLIMB COMPLETE"
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

    /// Every word and number in the rank hero, resolved as one unit so the
    /// displayed position and its denominator always come from the same
    /// measurement. See `LiveClimbSummaryRankHero`.
    private var rankHero: LiveClimbSummaryRankHero? {
        LiveClimbSummaryRankHero.make(
            isClimbContext: climb != nil,
            moment: moment,
            standings: LiveClimbSummaryRankHero.standings(
                isClimbContext: climb != nil,
                sources: rankSources
            ),
            sync: LiveClimbSummaryRankHero.SyncState(
                phase: publicResultStatus?.phase,
                hasRankContext: hasCompletionRankContext,
                rankResolution: rankResolution
            ),
            copy: LiveClimbSummaryRankHero.Copy(
                labelOverride: rankingLabelOverride,
                completedDetailOverride: completedDetailOverride
            )
        )
    }

    private var hasCompletionRankContext: Bool {
        ranksOnLeaderboard && effectiveLeaderboardContext != nil
    }

    /// Every rank the surface holds, each still paired with the total its own
    /// source reported. `LiveClimbSummaryRankHero.standings` decides which one
    /// wins and what population it may claim.
    private var rankSources: LiveClimbSummaryRankHero.Sources {
        typealias Reading = LiveClimbSummaryRankHero.Reading

        let status = publicResultStatus

        return LiveClimbSummaryRankHero.Sources(
            callerSupplied: LiveClimbSummaryRankHero.Standing(
                rank: leaderboardRank,
                total: leaderboardTotal,
                basis: leaderboardRankBasis
            ),
            syncedSnapshot: Reading(
                rank: status?.rankSnapshot?.rank,
                total: status?.rankSnapshot?.completedCount
            ),
            publishStatus: Reading(
                rank: status?.publishStatus?.rankAtCompletion,
                total: status?.publishStatus?.completedCountAtCompletion
            ),
            fetchedSnapshot: Reading(
                rank: frozenCompletionRank?.rank,
                total: frozenCompletionRank?.completedCount
            ),
            computed: Reading(
                rank: computedCompletionRank?.rank,
                total: computedCompletionRank?.completedCount
            )
        )
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
            let hero = rankHero
            TelemetryManager.shared.track(
                LiveClimbAnalyticsEvent.summaryViewed(
                    climb: climb,
                    rank: hero?.standing?.rank,
                    rankTotal: hero?.total
                )
            )
        }
    }

    /// A completed climb's rank is permanent, so a reopened summary reads the frozen value from
    /// disk and returns without touching the network - no snapshot fetch, no publish poll, no
    /// recomputation. Everything below the early return runs only while the result is still
    /// settling on the server.
    @MainActor
    private func resolveCompletionRank() async {
        guard hasCompletionRankContext,
              let context = effectiveLeaderboardContext else {
            rankResolution = .settled
            return
        }

        let completedRankService = CompletedClimbRankService.shared
        let workoutId = workout.id.uuidString

        if let frozen = completedRankService.frozenRank(context: context, workoutId: workoutId) {
            frozenCompletionRank = frozen
            rankResolution = .settled
            return
        }

        guard rankResolution != .resolving else { return }

        rankResolution = .resolving
        defer { rankResolution = .settled }
        computedCompletionRank = nil

        if let resolved = await completedRankService.resolveFrozenRank(
            context: context,
            workoutId: workoutId
        ) {
            frozenCompletionRank = resolved
            await mirrorFinisherStatus(context: context)
            return
        }

        guard !Task.isCancelled else { return }

        if let climb {
            await resultSyncStore.refreshUntilRankPublished(
                workout: workout,
                climb: climb
            )
            if let rankSnapshot = resultSyncStore.status(for: workout.id)?.rankSnapshot {
                frozenCompletionRank = rankSnapshot
                await mirrorFinisherStatus(context: context)
                return
            }
        }

        guard !Task.isCancelled else { return }

        // The server has not ranked this workout yet, so there is nothing to freeze. Show today's
        // standing, which names itself as today's standing, and leave the permanent value to land
        // on a later visit.
        let completionDurationSeconds = workout.duration
        let finalSteps = workout.steps
        async let fetchedRank = LiveReplayLeaderboardService.shared.fetchCompletionRank(
            context: context,
            completionDurationSeconds: completionDurationSeconds,
            finalSteps: finalSteps
        )

        await mirrorFinisherStatus(context: context)

        do {
            computedCompletionRank = try await fetchedRank
        } catch {
#if DEBUG
            debugLog("Live Climb summary current standing fetch failed: \(error.localizedDescription)")
#endif
        }
    }

    /// Keeps the attempt's `globalCompletionOrder` current, which the First Ascent count and the
    /// "Nth finisher" line read. Best-effort and always called after the rank has been published to
    /// state, so a failure here never blocks or changes what the hero shows.
    ///
    /// Deliberately skipped on the frozen-on-device path: a reopened summary makes no request at
    /// all, and every other completed-climb surface refreshes this value anyway.
    @MainActor
    private func mirrorFinisherStatus(context: LiveReplayLeaderboardContext) async {
        guard let climb, !Task.isCancelled else { return }

        guard let finisherStatus = try? await LiveReplayLeaderboardService.shared
            .fetchCurrentUserFinisherStatus(context: context) else {
            return
        }

        try? ClimbService.shared.mirrorFinisherStatus(
            finisherStatus,
            for: climb,
            modelContext: modelContext
        )
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
                frozenCompletionRank = rankSnapshot
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
        leaderboardRankBasis: .liveSession,
        allowsRatingPrompt: true,
        onDone: {}
    )
    .modelContainer(for: [Workout.self, ClimbAttempt.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self], inMemory: true)
}
