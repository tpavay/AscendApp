import SwiftUI

/// The Just Me tab for a climb that carries a progress cut-out: the landmark filling in with
/// colour from its base as recorded steps climb it, beside or above the live metrics. Climbs
/// without a cut-out keep `LiveClimbJustMeView`'s photo layout.
///
/// Two arrangements, picked by the landmark's shape (`ClimbProgressArtwork.layout`): a tall,
/// narrow landmark stands on the left with the metrics in a column beside it; a wide, stocky one
/// runs across the full width with the metrics in a two-by-two grid below. The readings, their
/// type and the chrome around them are the same in both, so the screen reads as one design
/// whatever the landmark's shape.
///
/// The phone sits on the stair stepper's console, an arm's length or more from the climber, so
/// the numbers are sized to be read from there: their type grows with the height the screen has
/// to give rather than holding one small size.
///
/// Heart rate is not among these metrics: on this tab it reads in the top chrome, beside the
/// climb name (`LiveClimbSessionView.topChrome`).
struct LiveClimbJustMeLandmarkView: View {
    let viewModel: LiveClimbSessionViewModel
    let loaded: LoadedClimbProgressArtwork

    private var artwork: ClimbProgressArtwork { loaded.artwork }

    private static let columnSpacing: CGFloat = 14
    private static let stackedSpacing: CGFloat = 22
    private static let gridSpacing: CGFloat = 16
    private static let gridInset: CGFloat = 4
    private static let paceSpacing: CGFloat = 12
    /// The metrics' share of the tab's width; the landmark is drawn at its own proportions in
    /// what is left.
    private static let metricsWidthFraction: CGFloat = 0.52
    /// What the view model shows for a reading it cannot state yet (no rank, too little clock).
    private static let placeholderValue = "—"

    var body: some View {
        GeometryReader { proxy in
            let metricsWidth = (proxy.size.width * Self.metricsWidthFraction).rounded()
            // Each stat's slot: the side-by-side column, or one cell of the stacked grid.
            let statWidth = artwork.layout == .stacked
                ? (proxy.size.width - Self.gridInset * 2 - Self.columnSpacing) / 2
                : metricsWidth
            let type = MetricType(
                availableHeight: proxy.size.height,
                statWidth: statWidth,
                paceWidth: (statWidth - Self.paceSpacing) / 2,
                stepsTemplate: LiveClimbMetricFontSizing.template(
                    for: (viewModel.mode.targetStepCount ?? 99_999).formatted()
                )
            )

            if artwork.layout == .stacked {
                VStack(spacing: Self.stackedSpacing) {
                    landmark
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    metricsGrid(type: type)
                }
            } else {
                HStack(alignment: .center, spacing: Self.columnSpacing) {
                    landmark
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    metricsColumn(type: type)
                        .frame(width: metricsWidth)
                        .frame(maxHeight: .infinity)
                }
            }
        }
        .padding(.bottom, 4)
    }

    private var landmark: some View {
        ClimbProgressArtworkView(
            artwork: artwork,
            image: loaded.image,
            completedSteps: viewModel.totalRecordedSteps,
            totalSteps: viewModel.mode.targetStepCount,
            previousBestFraction: viewModel.previousBestProgressFraction
        )
        .aspectRatio(artwork.visibleAspectRatio, contentMode: .fit)
    }

    /// The stacked layout's metrics: the same readings at the same sizes as the side-by-side
    /// column, in two rows of two under the full-width landmark.
    private func metricsGrid(type: MetricType) -> some View {
        VStack(alignment: .leading, spacing: Self.gridSpacing) {
            HStack(alignment: .top, spacing: Self.columnSpacing) {
                stepsMetric(type: type)
                metric(value: viewModel.elapsedClock, label: "ELAPSED", size: type.value, type: type)
            }

            HStack(alignment: .top, spacing: Self.columnSpacing) {
                metric(value: viewModel.currentRankDisplay, label: "CURRENT RANK", size: type.value, type: type)
                paceRow(type: type)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Self.gridInset)
    }

    /// Type sizes for the metrics, scaled to the height the tab has so a compact phone keeps
    /// every row on screen and a tall one spends its extra height on bigger numbers - and then
    /// capped so each stat's widest reading fits its slot (`LiveClimbMetricFontSizing`). The
    /// values are set at these sizes exactly and never shrink to fit a particular reading, so a
    /// pace going from 7 to 74 to 148 stays the same size in the same place.
    @MainActor
    private struct MetricType {
        let heroValue: CGFloat
        let value: CGFloat
        let paceValue: CGFloat
        let caption: CGFloat
        let label: CGFloat

        init(availableHeight: CGFloat, statWidth: CGFloat, paceWidth: CGFloat, stepsTemplate: String) {
            // Tuned so the column's four rows fill a 16 Pro's tab (~560pt) at full size and
            // still fit an SE's (~400pt) at the floor.
            let scale = min(max(availableHeight / 560, 0.7), 1)
            heroValue = LiveClimbMetricFontSizing.fittedSize(
                for: [stepsTemplate],
                width: statWidth,
                maximum: (76 * scale).rounded()
            )
            value = LiveClimbMetricFontSizing.fittedSize(
                for: [LiveClimbMetricFontSizing.elapsedTemplate, LiveClimbMetricFontSizing.rankTemplate],
                width: statWidth,
                maximum: (56 * scale).rounded()
            )
            paceValue = LiveClimbMetricFontSizing.fittedSize(
                for: [LiveClimbMetricFontSizing.paceTemplate],
                width: paceWidth,
                maximum: (56 * scale).rounded()
            )
            caption = (20 * scale).rounded()
            label = max((13 * scale).rounded(), 11)
        }
    }

    private func metricsColumn(type: MetricType) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            stepsMetric(type: type)

            Spacer(minLength: 8)

            metric(value: viewModel.elapsedClock, label: "ELAPSED", size: type.value, type: type)

            Spacer(minLength: 8)

            metric(value: viewModel.currentRankDisplay, label: "CURRENT RANK", size: type.value, type: type)

            Spacer(minLength: 8)

            paceRow(type: type)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Current and average pace side by side, each in a slot sized for a three-digit reading.
    /// Each half is too narrow for "CURRENT SPM" on one line at the label size, and letting it
    /// shrink alone left the pair's labels at two different sizes - so the unit sits on its own
    /// line under both, as the photo layout's pace card has it.
    private func paceRow(type: MetricType) -> some View {
        HStack(alignment: .top, spacing: Self.paceSpacing) {
            metric(value: viewModel.currentPaceDisplay, label: "CURRENT", unit: "SPM", size: type.paceValue, type: type)
            metric(value: viewModel.averagePaceDisplay, label: "AVG", unit: "SPM", size: type.paceValue, type: type, valueOpacity: 0.75)
        }
    }

    /// Completed steps over the climb's total, with the fraction the landmark is showing.
    private func stepsMetric(type: MetricType) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            valueText(viewModel.totalRecordedSteps.formatted(), size: type.heroValue)
                .foregroundStyle(.white)

            if let targetStepCount = viewModel.mode.targetStepCount {
                Text("of \(targetStepCount.formatted()) steps")
                    .font(.montserratSemiBold(size: type.caption))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(viewModel.totalProgressPercent.formatted() + "%")
                    .font(.montserratBold(size: type.caption))
                    .foregroundStyle(Color.accent)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// A stat value at its fixed size. The size is a fixed point size rather than a Dynamic
    /// Type-relative one because it is already the largest the slot holds; the shrink allowance
    /// is only a fallback for a reading longer than its slot's template (an hour-long clock, a
    /// four-digit rank), never something a normal reading triggers.
    private func valueText(_ value: String, size: CGFloat) -> some View {
        Text(value)
            .font(.custom(LiveClimbMetricFontSizing.valueFontName, fixedSize: size))
            .monospacedDigit()
            .contentTransition(.numericText())
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    private func metric(
        value: String,
        label: String,
        unit: String? = nil,
        size: CGFloat,
        type: MetricType,
        valueOpacity: Double = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            valueText(value, size: size)
                .foregroundStyle(.white.opacity(valueOpacity))
                // A dash is drawn at mid-height, well above where digits sit, so on its own over
                // a label it reads as floating. Nudged down to where a number's baseline would be.
                .offset(y: value == Self.placeholderValue ? size * 0.2 : 0)

            Text(label)
                .font(.montserratBold(size: type.label))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let unit {
                Text(unit)
                    .font(.montserratBold(size: type.label))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
