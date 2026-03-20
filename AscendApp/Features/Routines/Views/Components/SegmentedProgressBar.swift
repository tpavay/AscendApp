import SwiftUI

struct SegmentedProgressBar: View {
    let intervals: [RoutineInterval]
    let elapsedLabel: String
    let totalLabel: String
    let elapsedTime: TimeInterval

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: Metrics.labelSpacing) {
            HStack {
                Text(elapsedLabel)
                    .font(.montserratSemiBold(size: Metrics.elapsedLabelFontSize))
                    .foregroundStyle(.white.opacity(Metrics.elapsedLabelOpacity))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(totalLabel)
                    .font(.montserratMedium(size: Metrics.sideLabelFontSize))
                    .foregroundStyle(.white.opacity(Metrics.sideLabelOpacity))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .monospacedDigit()

            GeometryReader { geometry in
                let totalGapWidth = CGFloat(max(intervals.count - 1, 0)) * Metrics.segmentGap
                let availableWidth = max(geometry.size.width - totalGapWidth, 0)

                HStack(spacing: Metrics.segmentGap) {
                    ForEach(intervals.indices, id: \.self) { index in
                        let interval = intervals[index]
                        let width = segmentWidth(for: interval, availableWidth: availableWidth)
                        let fillFraction = fillFraction(for: index)
                        let segmentColor = segmentColor(for: interval)
                        let shape = SegmentShape(position: segmentPosition(for: index))

                        ZStack(alignment: .leading) {
                            shape
                                .fill(.white.opacity(Metrics.upcomingOpacity))

                            shape
                                .fill(segmentColor)
                                .frame(width: width * fillFraction)
                                .shadow(
                                    color: segmentColor.opacity(fillFraction > 0 ? Metrics.fillShadowOpacity : 0),
                                    radius: Metrics.fillShadowRadius,
                                    x: 0,
                                    y: 0
                                )
                        }
                        .frame(width: width, height: Metrics.barHeight)
                        .clipShape(shape)
                    }
                }
            }
            .frame(height: Metrics.barHeight)
        }
    }

    private var totalDuration: TimeInterval {
        intervals.reduce(0) { $0 + $1.duration }
    }

    private func segmentWidth(for interval: RoutineInterval, availableWidth: CGFloat) -> CGFloat {
        guard totalDuration > 0 else { return 0 }
        return max((interval.duration / totalDuration) * availableWidth, Metrics.minimumSegmentWidth)
    }

    private func fillFraction(for intervalIndex: Int) -> CGFloat {
        let startTime = intervals.prefix(intervalIndex).reduce(0) { $0 + $1.duration }
        let endTime = startTime + intervals[intervalIndex].duration

        if elapsedTime >= endTime {
            return 1
        }

        if elapsedTime <= startTime {
            return 0
        }

        let segmentElapsed = elapsedTime - startTime
        return CGFloat(min(max(segmentElapsed / intervals[intervalIndex].duration, 0), 1))
    }

    private func segmentColor(for interval: RoutineInterval) -> Color {
        Color.heatMapColor(
            for: interval.intensityTier.heatMapScore,
            colorScheme: colorScheme
        )
    }

    private func segmentPosition(for index: Int) -> SegmentShape.Position {
        if intervals.count == 1 {
            return .single
        }

        if index == 0 { return .leading }
        if index == intervals.count - 1 { return .trailing }
        return .middle
    }
}

private struct SegmentShape: Shape {
    enum Position {
        case single
        case leading
        case middle
        case trailing
    }

    let position: Position

    func path(in rect: CGRect) -> Path {
        switch position {
        case .single:
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: Metrics.outerCornerRadius,
                    bottomLeading: Metrics.outerCornerRadius,
                    bottomTrailing: Metrics.outerCornerRadius,
                    topTrailing: Metrics.outerCornerRadius
                )
            ).path(in: rect)
        case .leading:
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: Metrics.outerCornerRadius,
                    bottomLeading: Metrics.outerCornerRadius
                )
            ).path(in: rect)
        case .middle:
            Rectangle().path(in: rect)
        case .trailing:
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    bottomTrailing: Metrics.outerCornerRadius,
                    topTrailing: Metrics.outerCornerRadius
                )
            ).path(in: rect)
        }
    }
}

private enum Metrics {
    static let labelSpacing: CGFloat = 4
    static let elapsedLabelFontSize: CGFloat = 12
    static let elapsedLabelOpacity = 0.7
    static let sideLabelFontSize: CGFloat = 11
    static let sideLabelOpacity = 0.25
    static let segmentGap: CGFloat = 1
    static let barHeight: CGFloat = 1.5
    static let minimumSegmentWidth: CGFloat = 3
    static let outerCornerRadius: CGFloat = 1
    static let upcomingOpacity = 0.05
    static let fillShadowOpacity = 0.2
    static let fillShadowRadius: CGFloat = 4
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        SegmentedProgressBar(
            intervals: BuiltInRoutines.previewTemplates[6].intervals,
            elapsedLabel: "6:22",
            totalLabel: "20:00",
            elapsedTime: 382
        )
        .padding(24)
    }
}
