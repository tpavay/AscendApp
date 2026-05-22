import SwiftData
import SwiftUI

struct LiveClimbCompletionSummaryView: View {
    let climb: Climb?
    let workout: Workout
    let leaderboardRank: Int?
    let leaderboardTotal: Int?
    let onDone: () -> Void

    @Query(sort: \BestEffortCacheEntry.sortKey) private var bestEffortCacheEntries: [BestEffortCacheEntry]
    @State private var showingShareSheet = false
    @State private var completionRank: LiveReplayCompletionRank?
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
            WorkoutShareCarouselView(
                workout: workout,
                liveClimbRank: displayedRank,
                liveClimbRankTotal: displayedTotal
            )
        }
        .task {
            trackSummaryViewedIfNeeded()
            await loadCompletionRank()
        }
    }

    private var header: some View {
        HStack {
            Button {
                handleDoneTapped(surface: .backButton)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.accent)
                    .frame(width: 42, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("GLOBAL RANKING")
                .font(.montserratBold(size: 11))
                .foregroundStyle(.accent)

            if isLoadingCompletionRank && displayedRank == nil {
                Text("Ranking...")
                    .font(.montserratBold(size: 38))
                    .foregroundStyle(.accent)

                Text("CHECKING COMPLETED ATTEMPTS")
                    .font(.montserratBold(size: 10))
                    .foregroundStyle(.white.opacity(0.46))
            } else if let displayedRank {
                Text(displayedRank.ordinalText)
                    .font(.montserratBold(size: 52))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accent, .white],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(rankingSubtitle)
                    .font(.montserratBold(size: 10))
                    .foregroundStyle(.white.opacity(0.46))
            } else {
                Text("Pending")
                    .font(.montserratBold(size: 38))
                    .foregroundStyle(.accent)

                Text("RANKING UPDATES AFTER SYNC")
                    .font(.montserratBold(size: 10))
                    .foregroundStyle(.white.opacity(0.46))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Splits")
                    .font(.montserratBold(size: 21))
                    .foregroundStyle(.white)

                HStack(spacing: 5) {
                    Text(paceSplitSummaryText)
                        .foregroundStyle(.white.opacity(0.54))

                    Text("·")
                        .foregroundStyle(.white.opacity(0.34))

                    Text("avg")
                        .foregroundStyle(.white.opacity(0.54))

                    Text("\(averageSPMText) SPM")
                        .foregroundStyle(.white)
                }
                .font(.montserratMedium(size: 12))
                .lineLimit(1)
                .minimumScaleFactor(0.74)
            }

            LiveClimbPaceTrendChart(
                splits: paceSplits,
                averageStepsPerMinute: averageSPMValue
            )
            .frame(height: 84)
            .accessibilityHidden(true)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)

            VStack(spacing: 0) {
                ForEach(paceSplits) { split in
                    LiveClimbPaceSplitRow(
                        split: split,
                        minStepsPerMinute: minSplitSPM,
                        maxStepsPerMinute: maxSplitSPM
                    )

                    if split.id != paceSplits.last?.id {
                        Rectangle()
                            .fill(.white.opacity(0.06))
                            .frame(height: 1)
                    }
                }
            }
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

    private var rankingSubtitle: String {
        if let displayedTotal, displayedTotal > 0 {
            return "OUT OF \(displayedTotal.formatted())"
        }

        return climb == nil ? "JUST CLIMB COMPLETE" : "LIVE CLIMB COMPLETE"
    }

    private var averageSPMText: String {
        guard averageSPMValue > 0 else { return "0" }
        return Int(averageSPMValue.rounded()).formatted()
    }

    private var averageSPMValue: Double {
        guard let pace = workout.pace(for: .steps), pace > 0 else { return 0 }
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
        completionRank?.rank ?? leaderboardRank
    }

    private var displayedTotal: Int? {
        completionRank?.completedCount ?? leaderboardTotal
    }

    private var maxSplitSPM: Double {
        max(paceSplits.map(\.stepsPerMinute).max() ?? 0, 1)
    }

    private var minSplitSPM: Double {
        paceSplits.map(\.stepsPerMinute).min() ?? 0
    }

    private var paceSplitSummaryText: String {
        let segmentLabel = paceSplits.count == 1 ? "segment" : "segments"
        guard let firstSplit = paceSplits.first else {
            return "0 segments"
        }

        guard paceSplits.allSatisfy({ $0.durationSeconds == firstSplit.durationSeconds }) else {
            let finalDuration = paceSplits.last?.durationSeconds ?? firstSplit.durationSeconds
            return "\(paceSplits.count) \(segmentLabel), final \(clockTime(finalDuration))"
        }

        return "\(paceSplits.count) x \(clockTime(firstSplit.durationSeconds)) \(segmentLabel)"
    }

    private func handleDoneTapped(surface: LiveClimbAnalyticsEvent.SummaryDismissSurface) {
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
        guard completionRank == nil,
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

        do {
            completionRank = try await LiveReplayLeaderboardService.shared.fetchCompletionRank(
                context: context,
                completionDurationSeconds: workout.duration
            )
        } catch {
#if DEBUG
            print("Live Climb summary rank fetch failed: \(error.localizedDescription)")
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
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(timeRangeText)
                    .font(.montserratBold(size: 13))
                    .foregroundStyle(.white)
                    .frame(width: 94, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .monospacedDigit()

                Text("\(split.steps.formatted()) steps")
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)

                Text("\(Int(split.stepsPerMinute.rounded()).formatted())")
                    .font(.montserratBold(size: 19))
                    .foregroundStyle(.white)
                    .monospacedDigit()

                Text("SPM")
                    .font(.montserratBold(size: 8))
                    .foregroundStyle(.white.opacity(0.42))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.08))

                    Capsule()
                        .fill(Color.accent)
                        .frame(width: max(proxy.size.width * barProgress, 7))
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(timeRangeText), \(split.steps.formatted()) steps, \(Int(split.stepsPerMinute.rounded()).formatted()) steps per minute")
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
        onDone: {}
    )
    .modelContainer(for: [Workout.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self], inMemory: true)
}
