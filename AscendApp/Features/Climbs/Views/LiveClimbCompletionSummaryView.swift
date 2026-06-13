import SwiftData
import SwiftUI

struct LiveClimbCompletionSummaryView: View {
    let climb: Climb?
    let workout: Workout
    let leaderboardRank: Int?
    let leaderboardTotal: Int?
    let allowsRatingPrompt: Bool
    let onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BestEffortCacheEntry.sortKey) private var bestEffortCacheEntries: [BestEffortCacheEntry]
    @State private var showingShareSheet = false
    @State private var showingRatingEnjoymentPrompt = false
    @State private var completionFinisherStatus: LiveReplayFinisherStatus?
    @State private var completionSummary: LiveReplayLeaderboardSummary?
    @State private var isLoadingCompletionRank = false
    @State private var didTrackSummaryViewed = false

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
                    shareButton
                    doneButton
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
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
        .task {
            trackSummaryViewedIfNeeded()
            await loadCompletionRank()
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
            }

            Spacer(minLength: 0)

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

            LiveClimbPaceTrendChart(
                splits: paceSplits,
                averageStepsPerMinute: averageSPMValue
            )
            .frame(height: 118)
            .accessibilityHidden(true)
        }
        .padding(16)
        .background(summaryCardBackground)
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
        if isLoadingCompletionRank && displayedRank == nil {
            return "Ranking..."
        }

        if let displayedRank {
            return displayedRank.ordinalText
        }

        return "Pending"
    }

    private var rankingDetailText: String {
        if isLoadingCompletionRank && displayedRank == nil {
            return "CHECKING COMPLETED ATTEMPTS"
        }

        if displayedRank != nil {
            return climb == nil ? "WORKOUT COMPLETE" : "LIVE CLIMB COMPLETE"
        }

        return "RANKING UPDATES AFTER SYNC"
    }

    private var rankingStatusText: String {
        if isLoadingCompletionRank && displayedRank == nil {
            return "CHECKING"
        }

        if displayedRank != nil {
            return "COMPLETE"
        }

        return "PENDING"
    }

    private var rankingLabelText: String {
        climb == nil ? "GLOBAL RANK" : "FINISHER ORDER"
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

    private var displayedRank: Int? {
        if climb == nil {
            return leaderboardRank
        }

        return completionFinisherStatus?.globalCompletionOrder ??
            localFinisherOrder ??
            estimatedPendingFinisherOrder
    }

    private var displayedTotal: Int? {
        if climb == nil {
            return leaderboardTotal
        }

        let total = max(
            completionSummary?.completedCount ?? 0,
            leaderboardTotal ?? 0,
            completionFinisherStatus?.globalCompletionOrder ?? 0,
            localFinisherOrder ?? 0,
            estimatedPendingFinisherOrder ?? 0
        )

        return total > 0 ? total : nil
    }

    private var localFinisherOrder: Int? {
        guard let climb else { return nil }
        return ClimbService.shared
            .historySummary(for: climb, modelContext: modelContext)
            .globalCompletionOrder
    }

    private var estimatedPendingFinisherOrder: Int? {
        guard climb != nil,
              completionFinisherStatus == nil,
              localFinisherOrder == nil else {
            return nil
        }

        let knownCompletedCount = max(
            completionSummary?.completedCount ?? 0,
            leaderboardTotal ?? 0
        )

        return knownCompletedCount > 0 ? knownCompletedCount + 1 : nil
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
        guard completionFinisherStatus == nil,
              !isLoadingCompletionRank,
              let climb else {
            return
        }

        isLoadingCompletionRank = true
        defer {
            isLoadingCompletionRank = false
        }

        let context = LiveReplayLeaderboardContext.liveClimb(
            climbId: climb.id,
            targetSteps: climb.referenceStepCount
        )

        async let fetchedSummary = LiveReplayLeaderboardService.shared.fetchSummary(context: context)
        async let fetchedFinisherStatus = LiveReplayLeaderboardService.shared.fetchCurrentUserFinisherStatus(context: context)

        do {
            completionSummary = try await fetchedSummary
        } catch {
#if DEBUG
            print("Live Climb summary count fetch failed: \(error.localizedDescription)")
#endif
        }

        do {
            if let finisherStatus = try await fetchedFinisherStatus {
                completionFinisherStatus = finisherStatus
                try? ClimbService.shared.mirrorFinisherStatus(
                    finisherStatus,
                    for: climb,
                    modelContext: modelContext
                )
            }
        } catch {
#if DEBUG
            print("Live Climb summary finisher fetch failed: \(error.localizedDescription)")
#endif
        }
    }
}

private struct LiveClimbPaceTrendChart: View {
    let splits: [LiveClimbPaceSplit]
    let averageStepsPerMinute: Double

    private var values: [Double] {
        splits.map(\.stepsPerMinute)
    }

    private var axisBounds: (min: Double, max: Double) {
        let allValues = values + [averageStepsPerMinute].filter { $0 > 0 }
        guard let minValue = allValues.min(),
              let maxValue = allValues.max() else {
            return (0, 10)
        }

        let spread = max(maxValue - minValue, 1)
        let padding = max(spread * 0.34, 4)
        let lower = max(0, floor((minValue - padding) / 5) * 5)
        let upper = ceil((maxValue + padding) / 5) * 5

        if upper <= lower {
            return (lower, lower + 10)
        }

        return (lower, upper)
    }

    var body: some View {
        GeometryReader { proxy in
            let plotRect = CGRect(
                x: 30,
                y: 8,
                width: max(proxy.size.width - 30, 1),
                height: max(proxy.size.height - 18, 1)
            )
            let points = points(in: plotRect)
            let averageY = yPosition(for: averageStepsPerMinute, in: plotRect)
            let bounds = axisBounds

            ZStack(alignment: .topLeading) {
                axisLabel(Int(bounds.max).formatted())
                    .position(x: 13, y: plotRect.minY)

                axisLabel(Int(bounds.min).formatted())
                    .position(x: 13, y: plotRect.maxY)

                Path { path in
                    path.move(to: CGPoint(x: plotRect.minX, y: averageY))
                    path.addLine(to: CGPoint(x: plotRect.maxX, y: averageY))
                }
                .stroke(
                    .white.opacity(0.13),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 5])
                )

                Text("AVG \(Int(averageStepsPerMinute.rounded()).formatted())")
                    .font(.montserratBold(size: 8))
                    .foregroundStyle(.white.opacity(0.46))
                    .padding(.horizontal, 3)
                    .background(Color(hex: "17191B"))
                    .position(
                        x: plotRect.minX + 34,
                        y: max(plotRect.minY + 10, averageY - 10)
                    )

                areaPath(points: points, plotRect: plotRect)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accent.opacity(0.2),
                                Color.accent.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                linePath(points: points)
                    .stroke(
                        Color.accent,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )

                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(Color.accent)
                        .frame(width: 5, height: 5)
                        .position(point)
                }
            }
        }
    }

    private func axisLabel(_ text: String) -> some View {
        Text(text)
            .font(.montserratMedium(size: 9))
            .foregroundStyle(.white.opacity(0.42))
            .monospacedDigit()
    }

    private func points(in plotRect: CGRect) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        guard values.count > 1 else {
            return [
                CGPoint(
                    x: plotRect.midX,
                    y: yPosition(for: values[0], in: plotRect)
                )
            ]
        }

        let xStep = plotRect.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            CGPoint(
                x: plotRect.minX + CGFloat(index) * xStep,
                y: yPosition(for: value, in: plotRect)
            )
        }
    }

    private func yPosition(for value: Double, in plotRect: CGRect) -> CGFloat {
        let bounds = axisBounds
        let range = max(bounds.max - bounds.min, 1)
        let normalizedValue = min(max((value - bounds.min) / range, 0), 1)
        return plotRect.maxY - CGFloat(normalizedValue) * plotRect.height
    }

    private func linePath(points: [CGPoint]) -> Path {
        Path { path in
            guard let firstPoint = points.first else { return }
            path.move(to: firstPoint)

            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    private func areaPath(points: [CGPoint], plotRect: CGRect) -> Path {
        Path { path in
            guard let firstPoint = points.first,
                  let lastPoint = points.last else {
                return
            }

            path.move(to: CGPoint(x: firstPoint.x, y: plotRect.maxY))
            path.addLine(to: firstPoint)

            for point in points.dropFirst() {
                path.addLine(to: point)
            }

            path.addLine(to: CGPoint(x: lastPoint.x, y: plotRect.maxY))
            path.closeSubpath()
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

                        Text("SPM")
                            .font(.montserratBold(size: 8))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(width: 54, alignment: .trailing)
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
