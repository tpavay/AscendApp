import Charts
import SwiftUI

/// Reusable smooth gradient line chart — the lime monotone curve shared across Ascend
/// (the profile's weekly steps trend, the live-climb SPM trend, etc.). Renders a gradient
/// area + a smooth monotone line, with optional point markers, a dashed average line, and
/// min/max y-axis labels. Pass a plain `[Double]`; the x-axis is just the sample index.
struct AscendTrendChart: View {
    let values: [Double]
    var average: Double?
    var showsPointMarkers: Bool
    var highlightsLastPoint: Bool
    var showsBoundsLabels: Bool
    var lineColor: Color

    init(
        values: [Double],
        average: Double? = nil,
        showsPointMarkers: Bool = false,
        highlightsLastPoint: Bool = false,
        showsBoundsLabels: Bool = false,
        lineColor: Color = .accent
    ) {
        self.values = values
        self.average = average
        self.showsPointMarkers = showsPointMarkers
        self.highlightsLastPoint = highlightsLastPoint
        self.showsBoundsLabels = showsBoundsLabels
        self.lineColor = lineColor
    }

    var body: some View {
        Chart {
            if let average, average > 0 {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(.white.opacity(0.16))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 5]))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("AVG \(Int(average.rounded()).formatted())")
                            .font(.montserratBold(size: 8))
                            .foregroundStyle(.white.opacity(0.46))
                    }
            }

            ForEach(points) { point in
                AreaMark(
                    x: .value("Index", point.index),
                    y: .value("Value", point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [lineColor.opacity(0.28), lineColor.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Index", point.index),
                    y: .value("Value", point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(lineColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                if showsPointMarkers {
                    PointMark(
                        x: .value("Index", point.index),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(lineColor)
                    .symbolSize(26)
                }

                if highlightsLastPoint, point.index == values.count - 1 {
                    PointMark(
                        x: .value("Index", point.index),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(.white)
                    .symbolSize(50)
                }
            }
        }
        .chartYScale(domain: bounds.min...bounds.max)
        .chartXAxis(.hidden)
        .chartYAxis {
            if showsBoundsLabels {
                AxisMarks(position: .leading, values: [bounds.min, bounds.max]) { value in
                    AxisValueLabel {
                        if let raw = value.as(Double.self) {
                            Text(Int(raw).formatted())
                                .font(.montserratMedium(size: 9))
                                .foregroundStyle(.white.opacity(0.42))
                        }
                    }
                }
            }
        }
        .sentryMasked()
    }

    private var points: [IndexedValue] {
        values.enumerated().map { IndexedValue(index: $0.offset, value: $0.element) }
    }

    /// Mirrors the prior SPM-trend padding: pad the spread, snap to 5s, floor at 0.
    private var bounds: (min: Double, max: Double) {
        let all = values + (average.map { $0 > 0 ? [$0] : [] } ?? [])
        guard let minValue = all.min(), let maxValue = all.max() else {
            return (0, 10)
        }
        let spread = max(maxValue - minValue, 1)
        let padding = max(spread * 0.34, 4)
        let lower = max(0, (floor((minValue - padding) / 5) * 5))
        let upper = ceil((maxValue + padding) / 5) * 5
        return upper <= lower ? (lower, lower + 10) : (lower, upper)
    }
}

private struct IndexedValue: Identifiable {
    let index: Int
    let value: Double

    var id: Int { index }
}
