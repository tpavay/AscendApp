import SwiftUI

/// The "Just Me" tab of the live climb session: a large centered step-progress hero, an
/// animated summit bar carrying the previous-best marker directly beneath it, and a centered
/// grid of medium live stats (elapsed, rank, pace, heart rate) sitting directly below the
/// bar - a 2x2 grid when heart rate is present, two-and-one when it is not. Renders over the
/// climb's own hero photo (`LiveClimbSessionView.sessionBackground`) rather than a flat
/// background, so text throughout carries its own shadow.
struct LiveClimbJustMeView: View {
    let viewModel: LiveClimbSessionViewModel

    private static let statBoxSpacing: CGFloat = 12
    private static let statBoxHeight: CGFloat = 104

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepsHero
            summitBar
            statGrid
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    /// The tab's hero, driven by the session's goal type. A step goal measures current steps
    /// against the target; a duration goal measures elapsed time against the target instead,
    /// in the same "current of goal" shape; an open Just Climb has no target of any kind to
    /// measure a fraction against, so it falls back to the plain step count with a "STEPS"
    /// label.
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
            } else if let targetDurationClock = viewModel.targetDurationClock {
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text(viewModel.elapsedClock)
                        .font(.montserratBold(size: 52))
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Text("of")
                        .font(.montserratMedium(size: 22))
                        .foregroundStyle(.white.opacity(0.68))

                    Text(targetDurationClock)
                        .font(.montserratBold(size: 26))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.86))
                }
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text(viewModel.totalRecordedSteps.formatted())
                        .font(.montserratBold(size: 52))
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Text("STEPS")
                        .font(.montserratBold(size: 18))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.62))
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
    /// label is anchored to the fill, not the track. A step or duration goal both
    /// have a target to measure that fraction against; an open Just Climb has
    /// neither, so the bar and its percent don't render at all rather than
    /// showing a fraction of nothing.
    ///
    /// Where the climber has finished this tower before, `LiveReplayPreviousBestMarker`
    /// - the same marker the replay leaderboard row draws - overlays the bar at
    /// their previous-best position. Reused rather than redrawn: it already
    /// carries every locked invariant (single line, no comparison number, never
    /// fades) for a horizontal fill, which is exactly what this bar is. It only
    /// ever has a position to draw on a step goal (`previousBestProgressFraction`
    /// is step-based), so it stays absent on a duration goal.
    @ViewBuilder
    private var summitBar: some View {
        if viewModel.mode.targetStepCount != nil || viewModel.mode.targetDuration != nil {
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

    /// A centered grid directly below the summit bar: the top-left box and Current Rank on
    /// the first row always, then Pace and (when present) Heart Rate on the second - a 2x2
    /// grid with a strap connected, two-and-one without one. Heart rate only appears when
    /// `viewModel.liveHeartRateStatus` reports a remembered strap (`LiveClimbSessionView.
    /// topChrome` draws no heart-rate indicator on this tab, so heart rate reads in exactly
    /// one place). Both rows share one `GeometryReader`-computed column
    /// width so the lone Pace box on the second row - centered by the VStack's default
    /// alignment rather than stretched to fill - matches the width of the boxes above it
    /// exactly, keeping the two-and-one shape balanced instead of lopsided.
    private var statGrid: some View {
        GeometryReader { proxy in
            let columnWidth = (proxy.size.width - Self.statBoxSpacing) / 2

            VStack(spacing: Self.statBoxSpacing) {
                HStack(spacing: Self.statBoxSpacing) {
                    topLeftStatCard
                        .frame(width: columnWidth)
                    statCard(value: viewModel.currentRankDisplay, label: "CURRENT RANK")
                        .frame(width: columnWidth)
                }

                HStack(spacing: Self.statBoxSpacing) {
                    paceCard
                        .frame(width: columnWidth)
                    if let heartRateStatus = viewModel.liveHeartRateStatus {
                        heartRateCard(status: heartRateStatus)
                            .frame(width: columnWidth)
                    }
                }
            }
        }
        .frame(height: Self.statBoxHeight * 2 + Self.statBoxSpacing)
    }

    /// The grid's top-left box: elapsed time for every goal type except a duration goal,
    /// which has already moved elapsed time into the hero - so this box shows the step
    /// count instead, the slot's mirror image of the step-goal hero/box pairing.
    private var topLeftStatCard: some View {
        if viewModel.mode.targetDuration != nil {
            return statCard(value: viewModel.totalRecordedSteps.formatted(), label: "STEPS")
        }

        return statCard(value: viewModel.elapsedClock, label: "ELAPSED")
    }

    /// Current pace and the whole-climb average sit side by side, each labeled directly -
    /// "CURRENT"/"SPM" and "AVERAGE"/"SPM" - with no "pace" heading above them.
    private var paceCard: some View {
        HStack(alignment: .center, spacing: 16) {
            paceColumn(value: viewModel.currentPaceDisplay, label: "CURRENT", valueSize: 24, valueOpacity: 1)
            paceColumn(value: viewModel.averagePaceDisplay, label: "AVERAGE", valueSize: 20, valueOpacity: 0.75)
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
                .font(.montserratBold(size: 10))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("SPM")
                .font(.montserratBold(size: 8))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.montserratBold(size: 26))
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(label)
                .font(.montserratBold(size: 10))
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

    /// The heart-rate box: the zone ring badge (`LiveHeartRateZoneRingBadge`) that used to sit
    /// in the top chrome, reused inline rather than redrawn, with a caption beneath it to match
    /// the grid's other cards. This is now the tab's only heart-rate surface. Drawn considerably larger
    /// than its original top-chrome size so its BPM number carries the same visual weight as
    /// the 24-26pt values in the grid's other three boxes.
    private func heartRateCard(status: LiveHeartRateStatus) -> some View {
        VStack(spacing: 8) {
            LiveHeartRateZoneRingBadge(status: status, diameter: 52, contentFontSize: 17)

            Text("HEART RATE")
                .font(.montserratBold(size: 10))
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
