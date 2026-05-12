import SwiftUI

struct RoutineEditorPreviewCard: View {
    let intervals: [RoutineInterval]
    let ghostInterval: RoutineInterval?

    @Environment(\.colorScheme) private var colorScheme

    private var previewIntervals: [RoutineInterval] {
        intervals + (ghostInterval.map { [$0] } ?? [])
    }

    var body: some View {
        HStack(spacing: 0) {
            LeadingAccentStripe(color: accentColor, width: 4, cornerRadius: 16)

            RoutineCardSurface(
                cornerRadius: 16,
                darkFillOpacity: 0.35,
                lightFillOpacity: 0.08,
                darkStrokeOpacity: 0,
                lightStrokeOpacity: 0
            ) {
                Group {
                    if previewIntervals.isEmpty {
                        emptyState
                    } else {
                        RoutineIntensityBarChart(
                            intervals: intervals,
                            height: 54,
                            minimumBarHeight: 11,
                            segmentGap: 2,
                            outerCornerRadius: 2,
                            widthMode: .proportionalToDuration,
                            ghostInterval: ghostInterval
                        )
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 92, alignment: .center)
                .padding(16)
            }
        }
        .clipShape(.rect(cornerRadius: 16))
    }

    private var accentColor: Color {
        Color.heatMapColor(
            for: averageTier.heatMapScore,
            colorScheme: colorScheme
        )
    }

    private var averageTier: IntensityTier {
        guard !previewIntervals.isEmpty else { return .minimal }

        let totals = previewIntervals.reduce(into: (weighted: 0.0, duration: 0.0)) { result, interval in
            result.weighted += Double(interval.resolvedLevel) * interval.duration
            result.duration += interval.duration
        }

        guard totals.duration > 0 else { return .minimal }
        return IntensityTier.from(level: Int((totals.weighted / totals.duration).rounded()))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach([0.28, 0.44, 0.62, 0.38, 0.52], id: \.self) { multiplier in
                    UnevenRoundedRectangle(
                        topLeadingRadius: multiplier == 0.28 ? 2 : 0,
                        bottomLeadingRadius: multiplier == 0.28 ? 2 : 0,
                        bottomTrailingRadius: multiplier == 0.52 ? 2 : 0,
                        topTrailingRadius: multiplier == 0.52 ? 2 : 0,
                        style: .continuous
                    )
                    .fill(Color.white.opacity(0.06))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54 * multiplier, alignment: .bottom)
                }
            }

            Text("Your routine preview builds here")
                .font(.montserratMedium(size: 13))
                .foregroundStyle(Color.customGray)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        RoutineEditorPreviewCard(intervals: [], ghostInterval: nil)
        RoutineEditorPreviewCard(
            intervals: BuiltInRoutines.previewTemplates[0].intervals,
            ghostInterval: RoutineInterval(duration: 120, intensityValue: 14)
        )
    }
    .padding(20)
    .preferredColorScheme(.dark)
}
