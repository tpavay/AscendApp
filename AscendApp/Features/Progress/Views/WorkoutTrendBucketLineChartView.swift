//
//  WorkoutTrendBucketLineChartView.swift
//  AscendApp
//
//  Line chart for displaying monthly aggregated trend data (Steps/min, Heart Rate)
//

import SwiftUI
import Charts

struct WorkoutTrendBucketLineChartView: View {
    let title: String
    let unitLabel: String
    let buckets: [WorkoutTrendBucket]
    let valueType: WorkoutTrendBucketValueType
    let colorScheme: ColorScheme

    @State private var selectedIndex: Int?

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return formatter
    }

    private var yScaleDomain: ClosedRange<Double> {
        let values = buckets.compactMap { valueForBucket($0) }
        let maxValue = values.max() ?? 0
        let minValue = values.min() ?? 0
        let padding = (maxValue - minValue) * 0.15
        return max(0, minValue - padding)...(maxValue + padding)
    }

    private var latestValueText: String? {
        guard let last = buckets.last, let value = valueForBucket(last) else { return nil }
        return "\(formattedValue(value)) \(unitLabel)"
    }

    private var selectedBucket: WorkoutTrendBucket? {
        guard let index = selectedIndex, buckets.indices.contains(index) else { return nil }
        return buckets[index]
    }

    private func valueForBucket(_ bucket: WorkoutTrendBucket) -> Double? {
        switch valueType {
        case .perMinute:
            return bucket.workoutCount > 0 ? bucket.metricPerMinute : nil
        case .averageHeartRate:
            return bucket.averageHeartRate
        case .total:
            return bucket.totalMetric
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
            // Line connecting monthly averages (only for months with data)
            ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                if let value = valueForBucket(bucket) {
                    LineMark(
                        x: .value("Index", index),
                        y: .value(title, value)
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)

                    PointMark(
                        x: .value("Index", index),
                        y: .value(title, value)
                    )
                    .foregroundStyle(selectedIndex == index ? Color.accentColor : (colorScheme == .dark ? .white : .black))
                    .symbolSize(selectedIndex == index ? 80 : 40)
                }
            }

            // Selection indicator
            if let index = selectedIndex, buckets.indices.contains(index), valueForBucket(buckets[index]) != nil {
                RuleMark(x: .value("Selected", index))
                    .foregroundStyle(Color.accentColor.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    .zIndex(-1)
            }
        }
        .chartXAxis {
            AxisMarks(values: Array(buckets.indices)) { value in
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
        .chartGesture { proxy in
            SpatialTapGesture()
                .onEnded { event in
                    handleTap(at: event.location, proxy: proxy)
                }
        }
        .frame(height: 200)
    }

    private func handleTap(at location: CGPoint, proxy: ChartProxy) {
        guard let xValue: Double = proxy.value(atX: location.x) else {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedIndex = nil
            }
            return
        }

        let index = Int(round(xValue))

        guard buckets.indices.contains(index), valueForBucket(buckets[index]) != nil else {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedIndex = nil
            }
            return
        }

        withAnimation(.easeOut(duration: 0.15)) {
            if selectedIndex == index {
                selectedIndex = nil
            } else {
                selectedIndex = index
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private func bucketLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        let month = formatter.string(from: date)
        return String(month.prefix(1))
    }

    private func tooltip(for bucket: WorkoutTrendBucket) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let fullLabel = formatter.string(from: bucket.startDate)
        let workoutLabel = "\(bucket.workoutCount) workout\(bucket.workoutCount == 1 ? "" : "s")"

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

            if let value = valueForBucket(bucket) {
                Text("\(formattedValue(value)) \(unitLabel)")
                    .font(.montserratBold(size: 16))
                    .foregroundStyle(.accent)
            }
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

    private func formattedValue(_ value: Double) -> String {
        formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }
}
