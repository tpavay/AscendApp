//
//  WorkoutTrendBarChartView.swift
//  AscendApp
//
//  Created by ChatGPT on 5/26/24.
//

import SwiftUI
import Charts

struct WorkoutTrendBarChartView: View {
    let title: String
    let unitLabel: String
    let buckets: [WorkoutTrendBucket]
    let valueType: WorkoutTrendBucketValueType
    let bucketStyle: TrendBucketStyle
    let range: WorkoutTrendRange
    let colorScheme: ColorScheme

    @State private var selectedIndex: Int?

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = valueType == .perMinute ? 1 : 0
        formatter.minimumFractionDigits = 0
        return formatter
    }

    private var yScaleDomain: ClosedRange<Double> {
        let maxValue = buckets.map { valueForBucket($0) }.max() ?? 0
        let upper = max(1, maxValue * 1.1)
        return 0...upper
    }

    private var latestValueText: String? {
        guard let last = buckets.last else { return nil }
        let value = valueForBucket(last)
        return "\(formattedValue(value)) \(unitLabel)"
    }

    private var selectedBucket: WorkoutTrendBucket? {
        guard let index = selectedIndex, buckets.indices.contains(index) else { return nil }
        return buckets[index]
    }

    private func valueForBucket(_ bucket: WorkoutTrendBucket) -> Double {
        switch valueType {
        case .total:
            return bucket.totalMetric
        case .perMinute:
            return bucket.metricPerMinute
        case .averageHeartRate:
            return bucket.averageHeartRate ?? 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView

            if let bucket = selectedBucket {
                tooltip(for: bucket)
            }

            chartView
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
        )
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.montserratSemiBold(size: 15))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)

                if let latestValueText = latestValueText {
                    Text("Latest: \(latestValueText)")
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
                }
            }

            Spacer()
        }
    }

    private var chartView: some View {
        Chart {
            ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                BarMark(
                    x: .value("Index", index),
                    y: .value(title, valueForBucket(bucket))
                )
                .foregroundStyle(selectedIndex == index ? Color.accentColor : Color.accentColor.opacity(0.85))
                .cornerRadius(4)
            }

            if let index = selectedIndex {
                RuleMark(x: .value("Selected", index))
                    .foregroundStyle(Color.accentColor.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
            }
        }
        .chartXAxis {
            AxisMarks(values: xAxisLabelIndices) { value in
                AxisGridLine()
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                AxisValueLabel {
                    if let index = value.as(Int.self), buckets.indices.contains(index) {
                        Text(bucketLabel(for: buckets[index].startDate))
                            .font(.montserratRegular(size: 10))
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                AxisValueLabel()
                    .font(.montserratRegular(size: 11))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
            }
        }
        .chartYScale(domain: yScaleDomain)
        .chartXScale(domain: -0.5...(Double(buckets.count) - 0.5))
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                selectBar(at: value.location, proxy: proxy, geometry: geometry)
                            }
                    )
                    .onTapGesture { location in
                        selectBar(at: location, proxy: proxy, geometry: geometry)
                    }
            }
        }
        .frame(height: 200)
    }

    private var xAxisLabelIndices: [Int] {
        guard !buckets.isEmpty else { return [] }

        switch bucketStyle {
        case .month:
            // For year view (12 months), show all labels
            return Array(buckets.indices)
        case .week:
            // For 6M view (~26 weeks), show every 4th label
            let stride = max(1, buckets.count / 6)
            return buckets.indices.filter { index in
                index % stride == 0 || index == buckets.count - 1
            }
        case .perWorkout:
            return Array(buckets.indices)
        }
    }

    private func bucketLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        switch bucketStyle {
        case .week:
            formatter.dateFormat = "MMM d"
        case .month:
            formatter.dateFormat = "MMM"
            let month = formatter.string(from: date)
            return String(month.prefix(1))
        case .perWorkout:
            formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: date)
    }

    private func selectBar(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        let plotFrame = geometry.frame(in: .local)
        guard plotFrame.contains(location) else { return }

        // Convert tap location to chart x value (index)
        guard let xValue: Double = proxy.value(atX: location.x) else { return }

        // Round to nearest integer index
        let index = Int(round(xValue))

        guard buckets.indices.contains(index) else { return }

        if selectedIndex != index {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedIndex = index
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func tooltip(for bucket: WorkoutTrendBucket) -> some View {
        let fullLabel = fullBucketLabel(for: bucket.startDate)
        let workoutLabel = "\(bucket.workoutCount) workout\(bucket.workoutCount == 1 ? "" : "s")"
        let valueLabel = "\(formattedValue(valueForBucket(bucket))) \(unitLabel)"

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(fullLabel)
                    .font(.montserratSemiBold(size: 13))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)

                Text(workoutLabel)
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .gray)
            }

            Spacer()

            Text(valueLabel)
                .font(.montserratBold(size: 16))
                .foregroundStyle(.accent)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func fullBucketLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        switch bucketStyle {
        case .week:
            formatter.dateFormat = "MMMM d, yyyy"
        case .month:
            formatter.dateFormat = "MMMM yyyy"
        case .perWorkout:
            formatter.dateFormat = "MMMM d, yyyy"
        }
        return formatter.string(from: date)
    }

    private func formattedValue(_ value: Double) -> String {
        formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }
}
