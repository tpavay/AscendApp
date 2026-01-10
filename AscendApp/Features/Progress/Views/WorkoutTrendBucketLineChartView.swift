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

    @State private var selectedDate: Date?

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return formatter
    }

    private var xScaleDomain: ClosedRange<Date> {
        guard let first = buckets.first?.startDate,
              let last = buckets.last?.startDate else {
            return Date()...Date()
        }
        return first...last
    }

    private var yScaleDomain: ClosedRange<Double> {
        let values = buckets.compactMap { valueForBucket($0) }
        let maxValue = values.max() ?? 0
        let minValue = values.min() ?? 0

        // Handle single data point or equal min/max by using percentage-based padding
        if maxValue == minValue {
            let padding = maxValue * 0.2
            let effectivePadding = max(padding, 1.0) // Ensure at least some padding
            return max(0, minValue - effectivePadding)...(maxValue + effectivePadding)
        }

        let padding = (maxValue - minValue) * 0.15
        return max(0, minValue - padding)...(maxValue + padding)
    }

    private var selectedBucket: WorkoutTrendBucket? {
        guard let selectedDate = selectedDate else { return nil }
        return buckets.first { bucket in
            Calendar.current.isDate(selectedDate, equalTo: bucket.startDate, toGranularity: .month)
        }
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
            Text(title)
                .font(.montserratSemiBold(size: 15))
                .foregroundStyle(colorScheme == .dark ? .white : .black)

            Spacer()
        }
    }

    private var chartView: some View {
        Chart {
            // Line connecting monthly averages (only for months with data)
            ForEach(buckets) { bucket in
                if let value = valueForBucket(bucket) {
                    LineMark(
                        x: .value("Month", bucket.startDate, unit: .month),
                        y: .value(title, value)
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)

                    PointMark(
                        x: .value("Month", bucket.startDate, unit: .month),
                        y: .value(title, value)
                    )
                    .foregroundStyle(isSelected(bucket) ? Color.accentColor : (colorScheme == .dark ? .white : .black))
                    .symbolSize(isSelected(bucket) ? 80 : 40)
                }
            }

            // Selection indicator
            if let bucket = selectedBucket, valueForBucket(bucket) != nil {
                RuleMark(x: .value("Selected", bucket.startDate, unit: .month))
                    .foregroundStyle(Color.accentColor.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    .zIndex(-1)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { value in
                AxisGridLine()
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                    .font(.montserratRegular(size: 10))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
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
        .chartXScale(domain: xScaleDomain)
        .chartYScale(domain: yScaleDomain)
        .chartGesture { proxy in
            SpatialTapGesture()
                .onEnded { event in
                    handleTap(at: event.location, proxy: proxy)
                }
        }
        .frame(height: 200)
    }

    private func isSelected(_ bucket: WorkoutTrendBucket) -> Bool {
        guard let selectedDate = selectedDate else { return false }
        return Calendar.current.isDate(selectedDate, equalTo: bucket.startDate, toGranularity: .month)
    }

    private func handleTap(at location: CGPoint, proxy: ChartProxy) {
        guard let tappedDate: Date = proxy.value(atX: location.x) else {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedDate = nil
            }
            return
        }

        // Find bucket with data for this date
        let tappedBucket = buckets.first { bucket in
            Calendar.current.isDate(tappedDate, equalTo: bucket.startDate, toGranularity: .month) &&
            valueForBucket(bucket) != nil
        }

        guard tappedBucket != nil else {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedDate = nil
            }
            return
        }

        withAnimation(.easeOut(duration: 0.15)) {
            if let current = selectedDate,
               Calendar.current.isDate(current, equalTo: tappedDate, toGranularity: .month) {
                selectedDate = nil
            } else {
                selectedDate = tappedDate
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
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

            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    selectedDate = nil
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.4) : .gray.opacity(0.5))
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
