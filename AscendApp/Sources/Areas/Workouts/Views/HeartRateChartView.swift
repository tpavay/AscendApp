//
//  HeartRateChartView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/28/25.
//

import SwiftUI
import Charts

struct HeartRateChartView: View {
    let heartRateData: [HeartRateDataPoint]
    let workoutStartTime: Date
    let workoutDuration: TimeInterval
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var rawSelectedTime: TimeInterval?
    @State private var selectedPoint: HeartRateDataPoint?
    
    // Use actual heart rate data timespan instead of workout duration
    private var actualStartTime: Date {
        heartRateData.first?.timestamp ?? workoutStartTime
    }
    
    private var actualEndTime: Date {
        heartRateData.last?.timestamp ?? workoutStartTime.addingTimeInterval(workoutDuration)
    }
    
    private var actualDuration: TimeInterval {
        actualEndTime.timeIntervalSince(actualStartTime)
    }
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    // Convert heart rate data to chart-friendly format with elapsed time
    private var chartData: [(elapsed: TimeInterval, heartRate: Int)] {
        heartRateData.map { point in
            (elapsed: point.timestamp.timeIntervalSince(actualStartTime), heartRate: point.heartRate)
        }
    }
    
    // Computed property to find the selected point based on raw selected time
    private var computedSelectedPoint: HeartRateDataPoint? {
        guard let rawSelectedTime = rawSelectedTime else { return nil }
        
        return heartRateData.min { point1, point2 in
            let distance1 = abs(point1.timestamp.timeIntervalSince(actualStartTime) - rawSelectedTime)
            let distance2 = abs(point2.timestamp.timeIntervalSince(actualStartTime) - rawSelectedTime)
            return distance1 < distance2
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            headerView
            
            if heartRateData.isEmpty {
                emptyStateView
            } else {
                chartView
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            Text("Heart Rate")
                .font(.montserratSemiBold(size: 20))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                if let selected = computedSelectedPoint {
                    Text("\(selected.heartRate) BPM")
                        .font(.montserratBold(size: 16))
                        .foregroundStyle(.red)
                    Text(formatDuration(selected.timestamp.timeIntervalSince(actualStartTime)))
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                } else {
                    // Invisible placeholder to maintain consistent height
                    Text("000 BPM")
                        .font(.montserratBold(size: 16))
                        .opacity(0)
                    Text("00:00")
                        .font(.montserratRegular(size: 12))
                        .opacity(0)
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.slash")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.4) : .gray)
            
            Text("No heart rate data available")
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
            ForEach(Array(chartData.enumerated()), id: \.offset) { _, data in
                heartRateLineMark(data: data)
            }
            
            // Selected point indicators
            if let selected = computedSelectedPoint {
                let elapsed = selected.timestamp.timeIntervalSince(actualStartTime)
                selectedPointMarks(elapsed: elapsed, heartRate: selected.heartRate)
            }
        }
        .frame(height: 200)
        .chartXScale(domain: 0...actualDuration)
        .padding(16)
        .chartXAxis { xAxisMarks }
        .chartYAxis { yAxisMarks }
        .chartXSelection(value: $rawSelectedTime)
        .animation(.easeInOut(duration: 0.2), value: rawSelectedTime)
        .chartBackground { _ in
            backgroundView
        }
    }
    
    private func heartRateLineMark(data: (elapsed: TimeInterval, heartRate: Int)) -> some ChartContent {
        LineMark(
            x: .value("Time", data.elapsed),
            y: .value("Heart Rate", data.heartRate)
        )
        .foregroundStyle(.red)
        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
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
        AxisMarks(values: [0, actualDuration / 4, actualDuration / 2, 3 * actualDuration / 4, actualDuration]) { value in
            if let elapsed = value.as(Double.self) {
                let anchor: UnitPoint = elapsed == actualDuration ? .topTrailing : (elapsed == 0 ? .topLeading : .top)
                AxisValueLabel(anchor: anchor) {
                    Text(formatDuration(elapsed))
                        .font(.montserratRegular(size: 10))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                }
                AxisGridLine()
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))
                AxisTick()
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))
            }
        }
    }
    
    private var yAxisMarks: some AxisContent {
        AxisMarks(position: .leading) { value in
            if let heartRate = value.as(Int.self) {
                AxisValueLabel {
                    Text("\(heartRate)")
                        .font(.montserratRegular(size: 10))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                }
                AxisGridLine()
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))
                AxisTick()
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))
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
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    let startTime = Date()
    let sampleData = [
        HeartRateDataPoint(timestamp: startTime, heartRate: 95),
        HeartRateDataPoint(timestamp: startTime.addingTimeInterval(300), heartRate: 120),
        HeartRateDataPoint(timestamp: startTime.addingTimeInterval(600), heartRate: 145),
        HeartRateDataPoint(timestamp: startTime.addingTimeInterval(900), heartRate: 155),
        HeartRateDataPoint(timestamp: startTime.addingTimeInterval(1200), heartRate: 140),
        HeartRateDataPoint(timestamp: startTime.addingTimeInterval(1500), heartRate: 125),
        HeartRateDataPoint(timestamp: startTime.addingTimeInterval(1800), heartRate: 105)
    ]
    
    HeartRateChartView(
        heartRateData: sampleData,
        workoutStartTime: startTime,
        workoutDuration: 1800
    )
    .padding()
}
