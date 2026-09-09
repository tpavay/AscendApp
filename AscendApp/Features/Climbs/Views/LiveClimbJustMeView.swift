import SwiftUI

/// The "Just Me" tab of the live climb session: a step-progress statement, an
/// animated summit bar carrying the previous-best marker, and a row of live
/// stats (elapsed, steps remaining, rank). Renders over the climb's own hero
/// photo (`LiveClimbSessionView.sessionBackground`) rather than a flat
/// background, so text throughout carries its own shadow.
struct LiveClimbJustMeView: View {
    let viewModel: LiveClimbSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepsHeader
            summitBar
            statRow
                .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var stepsHeader: some View {
        if let targetStepCount = viewModel.mode.targetStepCount {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(viewModel.totalRecordedSteps.formatted())
                    .font(.montserratBold(size: 30))
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text("of")
                    .font(.montserratMedium(size: 15))
                    .foregroundStyle(.white.opacity(0.68))

                Text("\(targetStepCount.formatted()) steps")
                    .font(.montserratBold(size: 17))
                    .foregroundStyle(.white.opacity(0.86))
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.55), radius: 5, y: 1)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        } else {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(viewModel.totalRecordedSteps.formatted())
                    .font(.montserratBold(size: 30))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                HStack(spacing: 4) {
                    Text("OPEN")
                        .font(.montserratBold(size: 14))
                        .foregroundStyle(.white)
                    Text("CLIMB")
                        .font(.montserratBold(size: 10))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            .shadow(color: .black.opacity(0.55), radius: 5, y: 1)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
    }

    /// A horizontal fill that animates toward `totalProgressFraction`, with the
    /// live percentage riding its trailing edge - it moves for free because the
    /// label is anchored to the fill, not the track. On an open Just Climb there
    /// is no target to measure a fraction against, so the bar and its percent
    /// don't render at all rather than showing a fraction of nothing.
    ///
    /// Where the climber has finished this tower before, `LiveReplayPreviousBestMarker`
    /// - the same marker the replay leaderboard row draws - overlays the bar at
    /// their previous-best position. Reused rather than redrawn: it already
    /// carries every locked invariant (single line, no comparison number, never
    /// fades) for a horizontal fill, which is exactly what this bar is.
    @ViewBuilder
    private var summitBar: some View {
        if viewModel.mode.targetStepCount != nil {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let fraction = min(max(viewModel.totalProgressFraction, 0), 1)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.black.opacity(0.32))

                    Capsule()
                        .fill(Color.accent)
                        .frame(width: width * fraction)
                        .overlay(alignment: .trailing) {
                            Text(viewModel.totalProgressPercent.formatted() + "%")
                                .font(.montserratBold(size: 12))
                                .foregroundStyle(Color.accent)
                                .shadow(color: .black.opacity(0.6), radius: 4)
                                .fixedSize()
                                .offset(x: 30)
                        }

                    if let previousBestProgressFraction = viewModel.previousBestProgressFraction {
                        LiveReplayPreviousBestMarker(
                            progress: previousBestProgressFraction,
                            trailingNumberInset: 40,
                            lineColor: .white
                        )
                    }
                }
            }
            .frame(height: 22)
            .animation(.easeOut(duration: 0.5), value: viewModel.totalProgressFraction)
        }
    }

    private var statRow: some View {
        HStack(spacing: 10) {
            statCard(value: viewModel.elapsedClock, label: "ELAPSED")
            statCard(value: remainingStepsDisplay, label: "REMAINING", isAccent: true)
            statCard(value: viewModel.currentRankDisplay, label: "CURRENT RANK")
        }
    }

    /// Steps left to the summit, or "—" on an open Just Climb, where there is no
    /// target to count down from - the same no-value convention `currentRankDisplay`
    /// already uses rather than inventing a second one.
    private var remainingStepsDisplay: String {
        guard let targetStepCount = viewModel.mode.targetStepCount else { return "—" }
        return max(targetStepCount - viewModel.totalRecordedSteps, 0).formatted()
    }

    private func statCard(value: String, label: String, isAccent: Bool = false) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.montserratBold(size: 22))
                .foregroundStyle(isAccent ? Color.accent : .white)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(label)
                .font(.montserratBold(size: 9))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.34))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }
}
