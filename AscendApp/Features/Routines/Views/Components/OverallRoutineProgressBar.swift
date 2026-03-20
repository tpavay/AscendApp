import SwiftUI

struct OverallRoutineProgressBar: View {
    let intervals: [RoutineInterval]
    let elapsed: String
    let total: String
    let elapsedTime: TimeInterval
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: Metrics.labelSpacing) {
            HStack {
                Text("0:00")
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(elapsed)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text(total)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.montserratMedium(size: Metrics.labelFontSize))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.72))

            GeometryReader { geometry in
                let totalGapWidth = CGFloat(max(intervals.count - 1, 0)) * Metrics.segmentGap
                let availableWidth = max(geometry.size.width - totalGapWidth, 0)

                HStack(spacing: Metrics.segmentGap) {
                    ForEach(Array(intervals.enumerated()), id: \.element.id) { index, interval in
                        let width = segmentWidth(
                            for: interval,
                            availableWidth: availableWidth
                        )
                        let fillFraction = fillFraction(for: index)

                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.white.opacity(0.12))

                            RoundedRectangle(cornerRadius: 2)
                                .fill(segmentColor(for: interval))
                                .frame(width: width * fillFraction)
                                .shadow(color: segmentColor(for: interval).opacity(fillFraction > 0 ? Metrics.fillShadowOpacity : 0), radius: Metrics.fillShadowRadius, x: 0, y: 0)
                        }
                        .frame(width: width, height: Metrics.barHeight)
                        .clipShape(.rect(cornerRadius: 2))
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
}

private enum Metrics {
    static let labelSpacing: CGFloat = 6
    static let labelFontSize: CGFloat = 11
    static let segmentGap: CGFloat = 2
    static let barHeight: CGFloat = 2
    static let minimumSegmentWidth: CGFloat = 4
    static let fillShadowOpacity = 0.35
    static let fillShadowRadius: CGFloat = 8
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        OverallRoutineProgressBar(
            intervals: BuiltInRoutines.previewTemplates[6].intervals,
            elapsed: "6:22",
            total: "20:00",
            elapsedTime: 382
        )
        .padding(20)
    }
}
