//
//  WorkoutTrendsCard.swift
//  AscendApp
//
//  Created by ChatGPT on 5/25/24.
//

import SwiftUI
import Charts

struct WorkoutTrendsCard: View {
    let workouts: [Workout]
    let selectedDate: Date
    let preferredMetric: WorkoutMetric
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    private var calendar: Calendar { Calendar.current }
    
    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter
    }
    
    private var monthlyWorkouts: [Workout] {
        workouts.filter { calendar.isDate($0.date, equalTo: selectedDate, toGranularity: .month) }
    }
    
    private var totalPoints: [WorkoutTrendPoint] {
        WorkoutTrendsBuilder.trendPoints(from: monthlyWorkouts, metric: .preferredTotal, preferredMetric: preferredMetric)
    }
    
    private var perMinutePoints: [WorkoutTrendPoint] {
        WorkoutTrendsBuilder.trendPoints(from: monthlyWorkouts, metric: .preferredPerMinute, preferredMetric: preferredMetric)
    }
    
    private var hasEnoughData: Bool {
        min(totalPoints.count, perMinutePoints.count) >= 2
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            
            if hasEnoughData {
                VStack(spacing: 12) {
                    WorkoutTrendChartView(
                        title: preferredMetric.displayName,
                        unitLabel: preferredMetric.unit,
                        points: totalPoints,
                        metricType: .preferredTotal,
                        preferredMetric: preferredMetric,
                        colorScheme: effectiveColorScheme
                    )
                    
                    WorkoutTrendChartView(
                        title: "\(preferredMetric.displayName) per Minute",
                        unitLabel: "\(preferredMetric.unit)/min",
                        points: perMinutePoints,
                        metricType: .preferredPerMinute,
                        preferredMetric: preferredMetric,
                        colorScheme: effectiveColorScheme
                    )
                }
            } else {
                emptyState
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                )
        )
    }
    
    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Trends")
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                Text("Workouts in \(monthFormatter.string(from: selectedDate))")
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
            }
            
            Spacer()
            
            NavigationLink {
                WorkoutTrendsView(
                    workouts: workouts,
                    initialMonth: selectedDate
                )
            } label: {
                HStack(spacing: 4) {
                    Text("View All")
                        .font(.montserratMedium(size: 14))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(.accent)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.4) : .gray.opacity(0.6))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Log 2 or more workouts to see your trends.")
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                Text("Charts unlock as soon as you have two workouts in this month.")
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
            }
        }
    }
}

struct WorkoutTrendChartView: View {
    let title: String
    let unitLabel: String
    let points: [WorkoutTrendPoint]
    let metricType: WorkoutTrendMetricType
    let preferredMetric: WorkoutMetric
    let colorScheme: ColorScheme
    
    @State private var selectedPoint: WorkoutTrendPoint?
    
    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = metricType == .preferredPerMinute ? 1 : 0
        formatter.minimumFractionDigits = 0
        return formatter
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }
    
    private var latestValueText: String? {
        guard let last = points.last else { return nil }
        return "\(formattedValue(last.value)) \(unitLabel)"
    }
    
    private var yScaleDomain: ClosedRange<Double> {
        let maxValue = points.map(\.value).max() ?? 0
        let upper = max(1, maxValue * 1.15)
        return 0...upper
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            
            if let selectedPoint = selectedPoint {
                tooltip(for: selectedPoint)
            }
            
            Chart {
                ForEach(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value(title, point.value)
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                    
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value(title, point.value)
                    )
                    .foregroundStyle(point.id == selectedPoint?.id ? Color.accentColor : (colorScheme == .dark ? .white : .black))
                    .symbolSize(point.id == selectedPoint?.id ? 80 : 40)
                }
                
                if let selected = selectedPoint {
                    RuleMark(x: .value("Selected Date", selected.date))
                        .foregroundStyle(Color.accentColor.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                        .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.montserratRegular(size: 10))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                    AxisValueLabel()
                        .font(.montserratRegular(size: 11))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
                }
            }
            .chartYScale(domain: yScaleDomain)
            .chartGesture { proxy in
                SpatialTapGesture()
                    .onEnded { event in
                        selectNearestPoint(at: event.location, proxy: proxy)
                    }
            }
            .frame(height: 180)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
        )
    }

    private func selectNearestPoint(at location: CGPoint, proxy: ChartProxy) {
        var nearestPoint: WorkoutTrendPoint?
        var nearestDistance: CGFloat = .infinity

        for point in points {
            guard let xPosition = proxy.position(forX: point.date),
                  let yPosition = proxy.position(forY: point.value) else { continue }

            let pointLocation = CGPoint(x: xPosition, y: yPosition)
            let distance = hypot(location.x - pointLocation.x, location.y - pointLocation.y)

            if distance < nearestDistance {
                nearestDistance = distance
                nearestPoint = point
            }
        }

        if let point = nearestPoint, nearestDistance < 50 {
            withAnimation(.easeOut(duration: 0.15)) {
                if selectedPoint?.id == point.id {
                    // Tap same point to deselect
                    selectedPoint = nil
                } else {
                    selectedPoint = point
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        } else {
            // Tapped far from any point - deselect
            withAnimation(.easeOut(duration: 0.15)) {
                selectedPoint = nil
            }
        }
    }
    
    private func tooltip(for point: WorkoutTrendPoint) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dateFormatter.string(from: point.date))
                        .font(.montserratSemiBold(size: 13))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)

                    Text(point.workout.name)
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .gray)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(formattedValue(point.value)) \(unitLabel)")
                    .font(.montserratBold(size: 16))
                    .foregroundStyle(.accent)
            }

            // Show additional stats for total metric chart
            if metricType == .preferredTotal {
                Divider()
                    .background(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))

                HStack(spacing: 16) {
                    // Pace
                    if let pace = point.workout.pace(for: preferredMetric) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(preferredMetric.unit)/min")
                                .font(.montserratRegular(size: 10))
                                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.5) : .gray)
                            Text(String(format: "%.1f", pace))
                                .font(.montserratSemiBold(size: 13))
                                .foregroundStyle(colorScheme == .dark ? .white : .black)
                        }
                    }

                    // Heart Rate
                    if let avgHR = point.workout.avgHeartRate {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Avg HR")
                                .font(.montserratRegular(size: 10))
                                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.5) : .gray)
                            Text("\(avgHR) bpm")
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
                        .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
                )
        )
    }
    
    private func formattedValue(_ value: Double) -> String {
        formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }
}
