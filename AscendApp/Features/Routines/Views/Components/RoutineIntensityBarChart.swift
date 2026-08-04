import SwiftUI

enum RoutineIntensityBarChartWidthMode: Sendable {
    case equalSegments
    case proportionalToDuration
}

struct RoutineIntensityBarChart: View {
    let intervals: [RoutineInterval]
    var height: CGFloat = 36
    var minimumBarHeight: CGFloat = 7
    var segmentGap: CGFloat = 2
    var outerCornerRadius: CGFloat = 2
    var widthMode: RoutineIntensityBarChartWidthMode = .equalSegments
    /// Draws an in-progress interval dashed at its own `order`. No caller passes it since the
    /// timeline builder replaced the editor's preview card; it is kept, with its tests, so the
    /// splice fix behind it is not silently reverted the day a preview needs a ghost again.
    var ghostInterval: RoutineInterval? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var chartSegments: [RoutineIntensityChartSegment] {
        RoutineIntensityChartSegment.segments(intervals: intervals, ghostInterval: ghostInterval)
    }

    var body: some View {
        GeometryReader { geometry in
            let segmentWidths = resolvedWidths(totalWidth: geometry.size.width)

            HStack(alignment: .bottom, spacing: segmentGap) {
                ForEach(Array(chartSegments.enumerated()), id: \.element.id) { index, segment in
                    let isFirst = index == chartSegments.startIndex
                    let isLast = index == chartSegments.index(before: chartSegments.endIndex)

                    segmentShape(isFirst: isFirst, isLast: isLast)
                        .fill(segmentFillColor(for: segment))
                        .frame(width: segmentWidths[safe: index] ?? 0)
                        .frame(height: segmentHeight(for: segment.interval), alignment: .bottom)
                        .overlay {
                            if segment.isGhost {
                                segmentShape(isFirst: isFirst, isLast: isLast)
                                    .stroke(
                                        segmentColor(for: segment.interval).opacity(0.45),
                                        style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                                    )
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(height: height)
    }

    private func segmentShape(isFirst: Bool, isLast: Bool) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? outerCornerRadius : 0,
            bottomLeadingRadius: isFirst ? outerCornerRadius : 0,
            bottomTrailingRadius: isLast ? outerCornerRadius : 0,
            topTrailingRadius: isLast ? outerCornerRadius : 0,
            style: .continuous
        )
    }

    private func segmentFillColor(for segment: RoutineIntensityChartSegment) -> Color {
        let baseColor = segmentColor(for: segment.interval)
        return segment.isGhost ? baseColor.opacity(0.12) : baseColor
    }

    /// By level rather than by tier, so the shape a climber drags in the builder is the shape
    /// they see everywhere else - level 16 and level 20 are no longer the same bar.
    private func segmentColor(for interval: RoutineInterval) -> Color {
        RoutineIntervalScale.color(of: interval, colorScheme: colorScheme)
    }

    private func segmentHeight(for interval: RoutineInterval) -> CGFloat {
        max(minimumBarHeight, height * RoutineIntervalScale.heightFraction(of: interval))
    }

    private func resolvedWidths(totalWidth: CGFloat) -> [CGFloat] {
        guard !chartSegments.isEmpty else { return [] }

        let totalGapWidth = segmentGap * CGFloat(max(chartSegments.count - 1, 0))
        let availableWidth = max(totalWidth - totalGapWidth, 0)

        switch widthMode {
        case .equalSegments:
            let width = availableWidth / CGFloat(chartSegments.count)
            return Array(repeating: width, count: chartSegments.count)

        case .proportionalToDuration:
            let totalDuration = chartSegments.reduce(0) { $0 + $1.interval.duration }
            guard totalDuration > 0 else {
                let width = availableWidth / CGFloat(chartSegments.count)
                return Array(repeating: width, count: chartSegments.count)
            }

            return chartSegments.map { segment in
                availableWidth * CGFloat(segment.interval.duration / totalDuration)
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

#Preview("Equal Widths") {
    RoutineIntensityBarChart(
        intervals: BuiltInRoutines.previewTemplates[0].intervals,
        height: 36,
        widthMode: .equalSegments
    )
    .padding(20)
    .preferredColorScheme(.dark)
}

#Preview("Proportional Widths") {
    RoutineIntensityBarChart(
        intervals: BuiltInRoutines.previewTemplates[5].intervals,
        height: 56,
        widthMode: .proportionalToDuration
    )
    .padding(20)
    .preferredColorScheme(.dark)
}
