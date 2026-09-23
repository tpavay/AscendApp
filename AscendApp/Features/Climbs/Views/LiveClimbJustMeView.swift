import SwiftUI

/// The "Just Me" tab of the live climb session: a large centered step-progress hero, an
/// animated summit bar carrying the previous-best marker directly beneath it, and a single
/// row of compact live stats (elapsed, rank, pace, heart rate) sitting just above the End
/// attempt button. Renders over the climb's own hero photo
/// (`LiveClimbSessionView.sessionBackground`) rather than a flat background, so text
/// throughout carries its own shadow.
struct LiveClimbJustMeView: View {
    let viewModel: LiveClimbSessionViewModel

    private static let statCardHeight: CGFloat = 84

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepsHero
            summitBar
            Spacer(minLength: 20)
            statRow
        }
        .frame(maxHeight: .infinity)
    }

    /// The tab's hero: current-vs-goal steps at a large, clearly legible size, centered above
    /// the summit bar. An open Just Climb has no goal to measure a fraction against, so it
    /// keeps the plain step count plus an "OPEN CLIMB" tag instead.
    @ViewBuilder
    private var stepsHero: some View {
        Group {
            if let targetStepCount = viewModel.mode.targetStepCount {
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text(viewModel.totalRecordedSteps.formatted())
                        .font(.montserratBold(size: 52))
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Text("of")
                        .font(.montserratMedium(size: 22))
                        .foregroundStyle(.white.opacity(0.68))

                    Text("\(targetStepCount.formatted()) steps")
                        .font(.montserratBold(size: 26))
                        .foregroundStyle(.white.opacity(0.86))
                }
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    Text(viewModel.totalRecordedSteps.formatted())
                        .font(.montserratBold(size: 52))
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    HStack(spacing: 5) {
                        Text("OPEN")
                            .font(.montserratBold(size: 18))
                        Text("CLIMB")
                            .font(.montserratBold(size: 13))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.55), radius: 5, y: 1)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: .infinity, alignment: .center)
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
                                .opacity(showsPercentLabel(fillWidth: width * fraction, width: width) ? 1 : 0)
                                .animation(
                                    .easeInOut(duration: 0.3),
                                    value: showsPercentLabel(fillWidth: width * fraction, width: width)
                                )
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

    /// Mirrors `LiveReplayPreviousBestMarker.showsLabel`: the percent label rides
    /// the fill's trailing edge via a fixed offset, so it needs the same amount of
    /// room held clear beyond the edge - or it fades rather than running past the
    /// bar as the fill nears full width.
    private func showsPercentLabel(fillWidth: CGFloat, width: CGFloat) -> Bool {
        width - fillWidth >= 40
    }

    /// One horizontal row above End attempt: elapsed, rank, pace, then heart rate last -
    /// heart rate only when `viewModel.liveHeartRateStatus` reports a remembered strap
    /// (`LiveClimbSessionView.topChrome` suppresses the top-right ring on this tab for the
    /// same reason, so heart rate reads in exactly one place). Dropping it from the `HStack`
    /// entirely, rather than hiding it in place, lets the remaining cards fill the freed
    /// width instead of leaving a gap. Card styling stays compact so four boxes still fit
    /// an iPhone SE without clipping; the pace card's own internals are unchanged from the
    /// merged pace work, just narrower.
    private var statRow: some View {
        HStack(spacing: 8) {
            statCard(value: viewModel.elapsedClock, label: "ELAPSED")
            statCard(value: viewModel.currentRankDisplay, label: "CURRENT RANK")
            paceCard
            if let heartRateStatus = viewModel.liveHeartRateStatus {
                heartRateCard(status: heartRateStatus)
            }
        }
        .frame(height: Self.statCardHeight)
    }

    /// Current pace and the whole-climb average sit side by side, each carrying its own
    /// "current"/"average" label directly beneath it so neither number reads as bare -
    /// the shared unit is named once, centered under both columns.
    private var paceCard: some View {
        VStack(spacing: 5) {
            HStack(alignment: .lastTextBaseline, spacing: 14) {
                paceColumn(value: viewModel.currentPaceDisplay, label: "CURRENT", valueSize: 20, valueOpacity: 1)
                paceColumn(value: viewModel.averagePaceDisplay, label: "AVERAGE", valueSize: 16, valueOpacity: 0.75)
            }

            Text("PACE (STEPS PER MINUTE)")
                .font(.montserratBold(size: 8))
                .tracking(0.2)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
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

    private func paceColumn(value: String, label: String, valueSize: CGFloat, valueOpacity: Double) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.montserratBold(size: valueSize))
                .foregroundStyle(.white.opacity(valueOpacity))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(label)
                .font(.montserratBold(size: 8))
                .tracking(0.2)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.montserratBold(size: 22))
                .foregroundStyle(.white)
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

    /// The heart-rate box: the exact top-right ring badge (`LiveHeartRateZoneRingBadge`)
    /// reused inline rather than redrawn, with a caption beneath it to match the row's
    /// other cards. This is now the tab's only heart-rate surface.
    private func heartRateCard(status: LiveHeartRateStatus) -> some View {
        VStack(spacing: 6) {
            LiveHeartRateZoneRingBadge(status: status)

            Text("HEART RATE")
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
