import SwiftUI

struct LiveClimbCompletionSummaryView: View {
    let climb: Climb
    let workout: Workout
    let leaderboardRank: Int?
    let leaderboardTotal: Int?
    let onDone: () -> Void

    @State private var settingsManager = SettingsManager.shared
    @State private var showingShareSheet = false
    @State private var completionRank: LiveReplayCompletionRank?
    @State private var isLoadingCompletionRank = false
    @State private var didTrackSummaryViewed = false

    private var paceSplits: [LiveClimbPaceSplit] {
        LiveClimbWorkoutSummaryData.paceSplits(
            for: workout,
            targetSteps: climb.referenceStepCount
        )
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
            Image(systemName: achievementIconName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.accent)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(0.06))
                )

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
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PACE SPLITS")
                        .font(.montserratBold(size: 11))
                        .foregroundStyle(.accent)

                    Text("\(paceSplitIntervalText) segments by steps/min")
                        .font(.montserratMedium(size: 9))
                        .foregroundStyle(.white.opacity(0.46))
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 3) {
                    Text("VERTICAL")
                        .font(.montserratBold(size: 8))
                        .foregroundStyle(.white.opacity(0.42))

                    Text(verticalClimbText.uppercased())
                        .font(.montserratBold(size: 12))
                        .foregroundStyle(.accent)
                }
            }

            VStack(spacing: 11) {
                ForEach(paceSplits) { split in
                    LiveClimbPaceSplitRow(
                        split: split,
                        maxStepsPerMinute: maxSplitSPM
                    )
                }
            }
        }
        .padding(16)
        .background(summaryCardBackground)
    }

    private var shareButton: some View {
        Button {
            TelemetryManager.shared.track(
                LiveClimbAnalyticsEvent.summaryShareTapped(
                    climb: climb,
                    rank: displayedRank,
                    rankTotal: displayedTotal
                )
            )
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

        return "LIVE CLIMB COMPLETE"
    }

    private var averageSPMText: String {
        guard let pace = workout.pace(for: .steps), pace > 0 else { return "0" }
        return Int(pace.rounded()).formatted()
    }

    private var achievementIconName: String {
        workout.hasPersonalRecords ? "trophy.fill" : "checkmark.seal.fill"
    }

    private var achievementTitle: String {
        workout.hasPersonalRecords ? "PERSONAL RECORD" : "CLIMB COMPLETE"
    }

    private var achievementSubtitle: String {
        if let record = workout.achievedPersonalRecords.first {
            return "\(record.displayName) · \(workout.durationFormatted)"
        }

        return "\(climb.name) saved to history"
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

    private var paceSplitIntervalText: String {
        let splitDuration = paceSplits.first?.durationSeconds ??
            LiveClimbWorkoutSummaryData.paceSplitDurationSeconds(
                for: max(Int(workout.duration.rounded(.down)), 1)
            )
        return timeIntervalText(seconds: splitDuration)
    }

    private var verticalClimbText: String {
        let verticalClimb = workout.totalVerticalClimb(
            stepHeight: settingsManager.stepHeight,
            measurementSystem: settingsManager.measurementSystem
        )
        let value = verticalClimb.formatted(.number.precision(.fractionLength(1)))
        return "\(value) \(settingsManager.measurementSystem.distanceAbbreviation)"
    }

    private func handleDoneTapped(surface: LiveClimbAnalyticsEvent.SummaryDismissSurface) {
        TelemetryManager.shared.track(
            LiveClimbAnalyticsEvent.summaryDoneTapped(
                climb: climb,
                surface: surface
            )
        )
        onDone()
    }

    private func trackSummaryViewedIfNeeded() {
        guard !didTrackSummaryViewed else { return }
        didTrackSummaryViewed = true
        TelemetryManager.shared.track(
            LiveClimbAnalyticsEvent.summaryViewed(
                climb: climb,
                rank: displayedRank,
                rankTotal: displayedTotal
            )
        )
    }

    @MainActor
    private func loadCompletionRank() async {
        guard completionRank == nil,
              !isLoadingCompletionRank else {
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

private struct LiveClimbPaceSplitRow: View {
    let split: LiveClimbPaceSplit
    let maxStepsPerMinute: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(timeRangeText)
                    .font(.montserratBold(size: 10))
                    .foregroundStyle(.white.opacity(0.76))
                    .frame(width: 72, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Text("\(split.steps.formatted()) steps")
                    .font(.montserratMedium(size: 9))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("\(Int(split.stepsPerMinute.rounded()).formatted())")
                    .font(.montserratBold(size: 13))
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
                        .frame(width: max(proxy.size.width * barProgress, 6))
                }
            }
            .frame(height: 7)
        }
    }

    private var barProgress: Double {
        guard maxStepsPerMinute > 0 else { return 0 }
        return min(max(split.stepsPerMinute / maxStepsPerMinute, 0), 1)
    }

    private var timeRangeText: String {
        "\(clockTime(split.startElapsedSeconds))-\(clockTime(split.endElapsedSeconds))"
    }
}

private func timeIntervalText(seconds: Int) -> String {
    let safeSeconds = max(seconds, 1)
    if safeSeconds < 60 {
        return "\(safeSeconds)-sec"
    }

    let minutes = safeSeconds / 60
    return minutes == 1 ? "1-min" : "\(minutes)-min"
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
            source: .headphoneMotion,
            personalRecordTypes: ["longest_duration"]
        ),
        leaderboardRank: 12,
        leaderboardTotal: 2_460,
        onDone: {}
    )
}
