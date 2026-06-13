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

    @State private var selectedDate: Date?

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

    private var selectedBucket: WorkoutTrendBucket? {
        guard let selectedDate = selectedDate else { return nil }
        // Find bucket that contains this date
        return buckets.first { bucket in
            Calendar.current.isDate(selectedDate, equalTo: bucket.startDate, toGranularity: .month)
        }
    }

    private func valueForBucket(_ bucket: WorkoutTrendBucket) -> Double {
        switch valueType {
        case .total:
            return bucket.totalMetric
        case .perMinute:
            return bucket.metricPerMinute
        case .averageHeartRate:
            return bucket.averageHeartRate ?? 0
        case .duration:
            return bucket.totalDuration / 60.0 // Return minutes
        case .workoutCount:
            return Double(bucket.workoutCount)
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
            // Bar marks for each bucket using Date with unit: .month
            ForEach(buckets) { bucket in
                BarMark(
                    x: .value("Month", bucket.startDate, unit: .month),
                    y: .value(title, valueForBucket(bucket))
                )
                .foregroundStyle(isSelected(bucket) ? Color.ascendAccent : Color.ascendAccent.opacity(0.85))
                .clipShape(.rect(cornerRadius: 4))
            }

            // Selection indicator
            if selectedDate != nil, let bucket = selectedBucket {
                RuleMark(x: .value("Selected", bucket.startDate, unit: .month))
                    .foregroundStyle(Color.ascendAccent.opacity(0.4))
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
        .chartYScale(domain: yScaleDomain)
        // Use tap gesture for persistent selection
        .chartGesture { proxy in
            SpatialTapGesture()
                .onEnded { event in
                    handleTap(at: event.location, proxy: proxy)
                }
        }
        .frame(height: 130)
    }

    private func isSelected(_ bucket: WorkoutTrendBucket) -> Bool {
        guard let selectedDate = selectedDate else { return false }
        return Calendar.current.isDate(selectedDate, equalTo: bucket.startDate, toGranularity: .month)
    }

    private func handleTap(at location: CGPoint, proxy: ChartProxy) {
        // Convert tap location to Date
        guard let tappedDate: Date = proxy.value(atX: location.x) else {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedDate = nil
            }
            return
        }

        // Find the bucket for this date
        let tappedBucket = buckets.first { bucket in
            Calendar.current.isDate(tappedDate, equalTo: bucket.startDate, toGranularity: .month)
        }

        guard tappedBucket != nil else {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedDate = nil
            }
            return
        }

        // Toggle selection
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
        let fullLabel = fullBucketLabel(for: bucket.startDate)
        let workoutLabel = "\(bucket.workoutCount) workout\(bucket.workoutCount == 1 ? "" : "s")"
        let valueLabel = "\(formattedValue(valueForBucket(bucket))) \(unitLabel)"

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
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

            // Show additional stats for monthly buckets (Year view) in the total chart
            if valueType == .total && bucket.workoutCount > 0 {
                Divider()
                    .background(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Avg \(unitLabel)/min")
                            .font(.montserratRegular(size: 10))
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.5) : .gray)
                        Text(bucket.metricPerMinute, format: .number.precision(.fractionLength(1)))
                            .font(.montserratSemiBold(size: 13))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                    }

                    if let avgHR = bucket.averageHeartRate {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Avg HR")
                                .font(.montserratRegular(size: 10))
                                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.5) : .gray)
                            Text("\(Int(avgHR)) bpm")
                                .font(.montserratSemiBold(size: 13))
                                .foregroundStyle(colorScheme == .dark ? .white : .black)
                        }
                    }

                    Spacer()
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.ascendAccent.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func fullBucketLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func formattedValue(_ value: Double) -> String {
        formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }
}
