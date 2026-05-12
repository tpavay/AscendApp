//
//  HeartRateChartView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/28/25.
//

import SwiftUI
import Charts

struct HeartRateChartDataSet: Equatable {
    static let minimumLineSampleCount = 3

    let points: [HeartRateChartPoint]
    let duration: TimeInterval
    let heartRateRange: ClosedRange<Int>
    let heartRateTickValues: [Int]

    var canPlotLine: Bool {
        let distinctElapsedValues = Set(points.map { Int($0.elapsed.rounded()) })
        return points.count >= Self.minimumLineSampleCount && distinctElapsedValues.count >= 2
    }

    init(
        samples: [HeartRateDataPoint],
        workoutStartTime: Date,
        workoutDuration: TimeInterval
    ) {
        let visibleDuration = max(workoutDuration, 1)
        let workoutEndTime = workoutStartTime.addingTimeInterval(visibleDuration)
        let tolerance: TimeInterval = 60
        let sortedSamples = samples
            .filter { sample in
                sample.heartRate > 0 &&
                    sample.timestamp >= workoutStartTime.addingTimeInterval(-tolerance) &&
                    sample.timestamp <= workoutEndTime.addingTimeInterval(tolerance)
            }
            .sorted { $0.timestamp < $1.timestamp }

        points = sortedSamples.enumerated().map { index, sample in
            let elapsed = sample.timestamp.timeIntervalSince(workoutStartTime)
            return HeartRateChartPoint(
                id: index,
                elapsed: min(max(elapsed, 0), visibleDuration),
                heartRate: sample.heartRate
            )
        }
        duration = visibleDuration

        let rates = points.map(\.heartRate)
        heartRateRange = Self.range(for: rates)
        heartRateTickValues = Self.tickValues(for: heartRateRange)
    }

    private static func range(for heartRates: [Int]) -> ClosedRange<Int> {
        guard let minRate = heartRates.min(), let maxRate = heartRates.max() else {
            return 60...180
        }

        if minRate == maxRate {
            return max(30, minRate - 5)...(maxRate + 5)
        }

        let padding = max(3, Int(ceil(Double(maxRate - minRate) * 0.1)))
        return max(30, minRate - padding)...(maxRate + padding)
    }

    private static func tickValues(for range: ClosedRange<Int>) -> [Int] {
        let distance = range.upperBound - range.lowerBound
        guard distance > 0 else { return [range.lowerBound] }

        let interval = Double(distance) / 4.0
        var ticks = (0...4).map { index in
            range.lowerBound + Int(round(Double(index) * interval))
        }
        ticks[0] = range.lowerBound
        ticks[4] = range.upperBound
        return ticks
    }
}

struct HeartRateChartPoint: Identifiable, Equatable {
    let id: Int
    let elapsed: TimeInterval
    let heartRate: Int
}

struct HeartRateChartView: View {
    let heartRateData: [HeartRateDataPoint]
    let workoutStartTime: Date
    let workoutDuration: TimeInterval
    let averageHeartRateBpm: Int?
    let maxHeartRateBpm: Int?
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var rawSelectedTime: TimeInterval?
    @State private var stickySelectedTime: TimeInterval?

    private var dataSet: HeartRateChartDataSet {
        HeartRateChartDataSet(
            samples: heartRateData,
            workoutStartTime: workoutStartTime,
            workoutDuration: workoutDuration
        )
    }
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var computedSelectedPoint: HeartRateChartPoint? {
        guard let activeTime = rawSelectedTime ?? stickySelectedTime else { return nil }

        return dataSet.points.min { point1, point2 in
            let distance1 = abs(point1.elapsed - activeTime)
            let distance2 = abs(point2.elapsed - activeTime)
            return distance1 < distance2
        }
    }

    private var averageHeartRate: Int? {
        if let averageHeartRateBpm {
            return averageHeartRateBpm
        }
        guard !heartRateData.isEmpty else { return nil }
        return heartRateData.map(\.heartRate).reduce(0, +) / heartRateData.count
    }

    private var maxHeartRate: Int? {
        maxHeartRateBpm ?? heartRateData.map(\.heartRate).max()
    }
    
    var body: some View {
        VStack(spacing: 16) {
            headerView
            
            if dataSet.canPlotLine {
                chartView
            } else {
                unavailableChartView
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 6) {
            // Top row: "Heart Rate" title + always-visible avg/max
            HStack {
                Text("Heart Rate")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                Spacer()

                HStack(spacing: 16) {
                    if let averageHeartRate {
                        HStack(spacing: 4) {
                            Text("Avg")
                                .font(.montserratRegular(size: 12))
                                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                            Text("\(averageHeartRate)")
                                .font(.montserratBold(size: 14))
                                .foregroundStyle(.red)
                        }
                    }
                    if let maxHeartRate {
                        HStack(spacing: 4) {
                            Text("Max")
                                .font(.montserratRegular(size: 12))
                                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                            Text("\(maxHeartRate)")
                                .font(.montserratBold(size: 14))
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            // Selected point row (appears when user taps the graph)
            if let selected = computedSelectedPoint {
                HStack {
                    Spacer()
                    Text("\(selected.heartRate) BPM")
                        .font(.montserratBold(size: 16))
                        .foregroundStyle(.red)
                    Text("at \(formatDuration(selected.elapsed))")
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: computedSelectedPoint != nil)
    }
    
    private var unavailableChartView: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.slash")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.4) : .gray)
            
            Text(heartRateData.isEmpty ? "No heart-rate samples available" : "Not enough heart-rate samples to chart")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                )
        )
    }
    
    private var chartView: some View {
        Chart {
            ForEach(dataSet.points) { data in
                heartRateLineMark(data: data)
            }
            
            if let selected = computedSelectedPoint {
                selectedPointMarks(elapsed: selected.elapsed, heartRate: selected.heartRate)
            }
        }
        .frame(height: 200)
        .chartXScale(domain: 0...dataSet.duration)
        .chartYScale(domain: dataSet.heartRateRange)
        .padding(16)
        .chartXAxis { xAxisMarks }
        .chartYAxis { yAxisMarks }
        .chartXSelection(value: $rawSelectedTime)
        .animation(.easeInOut(duration: 0.2), value: rawSelectedTime)
        .onChange(of: computedSelectedPoint) { oldValue, newValue in
            // Trigger haptic feedback when selection changes to a new heart rate value
            if let oldHR = oldValue?.heartRate, 
               let newHR = newValue?.heartRate,
               oldHR != newHR {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            } else if oldValue == nil && newValue != nil {
                // Initial selection
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            }
        }
        .onChange(of: rawSelectedTime) { _, newValue in
            if let newValue {
                stickySelectedTime = newValue
            }
        }
        .chartBackground { _ in
            backgroundView
        }
    }
    
    private func heartRateLineMark(data: HeartRateChartPoint) -> some ChartContent {
        LineMark(
            x: .value("Time", data.elapsed),
            y: .value("Heart Rate", data.heartRate)
        )
        .foregroundStyle(.red)
        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
    }
    
    @ChartContentBuilder
    private func selectedPointMarks(elapsed: TimeInterval, heartRate: Int) -> some ChartContent {
        PointMark(
            x: .value("Time", elapsed),
            y: .value("Heart Rate", heartRate)
        )
        .foregroundStyle(.red)
        .symbolSize(64)
        
        RuleMark(x: .value("Time", elapsed))
            .foregroundStyle(.red.opacity(0.3))
            .lineStyle(StrokeStyle(lineWidth: 1))
    }
    
    private var xAxisMarks: some AxisContent {
        AxisMarks(values: [0, dataSet.duration / 4, dataSet.duration / 2, 3 * dataSet.duration / 4, dataSet.duration]) { value in
            if let elapsed = value.as(Double.self) {
                let anchor: UnitPoint = elapsed == dataSet.duration ? .topTrailing : (elapsed == 0 ? .topLeading : .top)
                AxisValueLabel(anchor: anchor) {
                    Text(formatDuration(elapsed))
                        .font(.montserratRegular(size: 10))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.15) : .gray.opacity(0.25))
                AxisTick()
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.15) : .gray.opacity(0.25))
            }
        }
    }

    private var yAxisMarks: some AxisContent {
        AxisMarks(position: .leading, values: dataSet.heartRateTickValues) { value in
            if let heartRate = value.as(Int.self) {
                AxisValueLabel {
                    Text("\(heartRate)")
                        .font(.montserratRegular(size: 10))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.15) : .gray.opacity(0.25))
                AxisTick()
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.15) : .gray.opacity(0.25))
            }
        }
    }
    
    private var backgroundView: some View {
        Rectangle()
            .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
    }
}

#Preview {
    let startTime = Date()
    let sampleData = [
        HeartRateDataPoint(timestamp: startTime, heartRate: 70),
        HeartRateDataPoint(timestamp: startTime.addingTimeInterval(300), heartRate: 120),
        HeartRateDataPoint(timestamp: startTime.addingTimeInterval(600), heartRate: 145),
        HeartRateDataPoint(timestamp: startTime.addingTimeInterval(900), heartRate: 200),
        HeartRateDataPoint(timestamp: startTime.addingTimeInterval(1200), heartRate: 140),
        HeartRateDataPoint(timestamp: startTime.addingTimeInterval(1500), heartRate: 125),
        HeartRateDataPoint(timestamp: startTime.addingTimeInterval(1800), heartRate: 105)
    ]
    
    HeartRateChartView(
        heartRateData: sampleData,
        workoutStartTime: startTime,
        workoutDuration: 1800,
        averageHeartRateBpm: 129,
        maxHeartRateBpm: 200
    )
    .padding()
}
