import SwiftUI

/// The live Ascend Mountain read-out over the 3D world: the step count large enough to read
/// from a stair-stepper console, and one row of pace, time, floors and heart rate (spec 4, 20, 43).
///
/// Every number is the session's own - `LiveClimbSessionViewModel` stays the authority - so
/// this screen can never disagree with Classic. Where the climber stands is not here: it is the
/// race pill in the top chrome, which also opens who they race. `crowd` counts the climbers
/// racing beyond the pack drawn on the stairs, ahead and behind.
struct AscendMountainSessionHUD: View {
    let viewModel: LiveClimbSessionViewModel
    let debugState: MountainDebugState?
    let crowd: MountainCrowdCounts?

    private static let statSpacing: CGFloat = 10
    /// Clear space kept between a stat's value and the sides of its box.
    private static let statInset: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            readOut(width: proxy.size.width)
        }
    }

    private func readOut(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            stepsHero

            if let crowd, crowd.ahead > 0 {
                AscendMountainCrowdChip(count: crowd.ahead, side: .ahead)
                    .frame(maxWidth: .infinity)
            }

#if DEBUG
            if let debugState {
                AscendMountainDebugOverlay(state: debugState)
            }
#endif

            Spacer(minLength: 0)

            if let crowd, crowd.behind > 0 {
                AscendMountainCrowdChip(count: crowd.behind, side: .behind)
                    .frame(maxWidth: .infinity)
            }

            statRow(width: width)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var stepsHero: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(viewModel.totalRecordedSteps.formatted())
                    .font(.montserratBold(size: 60))
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text("STEPS")
                    .font(.montserratBold(size: 16))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.7))
            }

            if let goalLine {
                Text(goalLine)
                    .font(.montserratBold(size: 14))
                    .tracking(0.6)
                    .foregroundStyle(Color.accent)
            }
        }
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .shadow(color: .black.opacity(0.6), radius: 6, y: 1)
        .accessibilityElement(children: .combine)
    }

    /// What is left of the goal, when there is one; an open climb has no line at all.
    private var goalLine: String? {
        if let target = viewModel.mode.targetStepCount {
            let remaining = max(target - viewModel.totalRecordedSteps, 0)
            return "\(remaining.formatted()) TO GO"
        }
        if let targetClock = viewModel.targetDurationClock {
            return "GOAL \(targetClock)"
        }
        return nil
    }

    /// One row of boxes, every value at one size: the largest at which the widest reading any of
    /// them takes fits a box (`LiveClimbMetricFontSizing`). A strap adds a fourth box, and on a
    /// compact phone that is narrower than a clock at full size - letting each value shrink on
    /// its own left the row's numbers at different sizes and its boxes at different heights.
    private func statRow(width: CGFloat) -> some View {
        let beatsPerMinute = connectedBeatsPerMinute
        let boxCount: CGFloat = beatsPerMinute == nil ? 3 : 4
        let boxWidth = (width - Self.statSpacing * (boxCount - 1)) / boxCount
        let valueSize = LiveClimbMetricFontSizing.fittedSize(
            for: [
                LiveClimbMetricFontSizing.paceTemplate,
                LiveClimbMetricFontSizing.elapsedTemplate,
                LiveClimbMetricFontSizing.template(
                    for: Workout.stepsToFloors(viewModel.mode.targetStepCount ?? 99_999).formatted()
                ),
            ],
            width: boxWidth - Self.statInset * 2,
            maximum: 30
        )

        return HStack(spacing: Self.statSpacing) {
            stat(value: viewModel.currentPaceDisplay, label: "SPM", valueSize: valueSize)
            stat(value: viewModel.elapsedClock, label: "ELAPSED", valueSize: valueSize)
            stat(value: viewModel.displayedFloors.formatted(), label: "FLOORS", valueSize: valueSize)
            if let beatsPerMinute {
                stat(value: beatsPerMinute.formatted(), label: "BPM", valueSize: valueSize)
            }
        }
    }

    private var connectedBeatsPerMinute: Int? {
        guard case .connected(let beatsPerMinute, _) = viewModel.liveHeartRateStatus else { return nil }
        return beatsPerMinute
    }

    /// The value is set at a fixed point size rather than a Dynamic Type-relative one because it
    /// is already the largest its box holds. The shrink allowance is only a fallback for a
    /// reading longer than its template - an hour-long clock - and the hidden digit holds the
    /// line's height while it applies, so that box stays level with its neighbours.
    private func stat(value: String, label: String, valueSize: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text("8")
                .hidden()
                .frame(maxWidth: .infinity)
                .overlay {
                    Text(value)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, Self.statInset)
                }
                .font(.custom(LiveClimbMetricFontSizing.valueFontName, fixedSize: valueSize))

            Text(label)
                .font(.montserratBold(size: 11))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
