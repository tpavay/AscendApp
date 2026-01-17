//
//  WorkoutTrendsView.swift
//  AscendApp
//
//  Created by ChatGPT on 5/25/24.
//

import SwiftUI
import Charts

struct WorkoutTrendsView: View {
    let workouts: [Workout]
    let initialMonth: Date
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared
    @State private var selectedRange: WorkoutTrendRange = .thisMonth
    @State private var trendAnchor: Date = Date()
    @State private var showingInfoTooltip = false
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    private var calendar: Calendar { Calendar.current }
    private var activePreferredMetric: WorkoutMetric { settingsManager.preferredWorkoutMetric }
    
    private var filteredWorkouts: [Workout] {
        guard let interval = selectedRange.dateInterval(using: calendar, anchor: trendAnchor) else { return [] }
        return workouts.filter { interval.contains($0.date) }
    }
    
    private var totalPoints: [WorkoutTrendPoint] {
        WorkoutTrendsBuilder.trendPoints(from: filteredWorkouts, metric: .preferredTotal, preferredMetric: activePreferredMetric)
    }
    
    private var perMinutePoints: [WorkoutTrendPoint] {
        WorkoutTrendsBuilder.trendPoints(from: filteredWorkouts, metric: .preferredPerMinute, preferredMetric: activePreferredMetric)
    }
    
    private var totalBuckets: [WorkoutTrendBucket] {
        WorkoutTrendsBuilder.trendBuckets(from: filteredWorkouts, preferredMetric: activePreferredMetric, range: selectedRange, calendar: calendar, anchor: trendAnchor)
    }

    private var perMinuteBuckets: [WorkoutTrendBucket] {
        WorkoutTrendsBuilder.trendBuckets(from: filteredWorkouts, preferredMetric: activePreferredMetric, range: selectedRange, calendar: calendar, anchor: trendAnchor)
    }
    
    private var heartRatePoints: [WorkoutTrendPoint] {
        WorkoutTrendsBuilder.trendPoints(from: filteredWorkouts, metric: .averageHeartRate, preferredMetric: activePreferredMetric)
    }

    // MARK: - Summary Stats

    private var totalMetricSum: Int {
        filteredWorkouts.reduce(0) { $0 + $1.metricValue(for: activePreferredMetric) }
    }

    private var averageMetricPerMinute: Double? {
        let totalMetric = filteredWorkouts.reduce(0.0) { $0 + Double($1.metricValue(for: activePreferredMetric)) }
        let totalDuration = filteredWorkouts.reduce(0.0) { $0 + $1.duration }
        let minutes = totalDuration / 60.0
        guard minutes > 0 else { return nil }
        return totalMetric / minutes
    }

    private var averageHeartRate: Int? {
        let heartRates = filteredWorkouts.compactMap(\.avgHeartRate)
        guard !heartRates.isEmpty else { return nil }
        return heartRates.reduce(0, +) / heartRates.count
    }

    private var totalDuration: TimeInterval {
        filteredWorkouts.reduce(0.0) { $0 + $1.duration }
    }

    private var workoutCount: Int {
        filteredWorkouts.count
    }

    private var durationPoints: [WorkoutTrendPoint] {
        WorkoutTrendsBuilder.trendPoints(from: filteredWorkouts, metric: .duration, preferredMetric: activePreferredMetric)
    }

    // MARK: - Previous Period Stats (for comparison)

    private var previousPeriodAnchor: Date {
        switch selectedRange {
        case .thisWeek:
            return calendar.date(byAdding: .weekOfYear, value: -1, to: trendAnchor) ?? trendAnchor
        case .thisMonth:
            return calendar.date(byAdding: .month, value: -1, to: trendAnchor) ?? trendAnchor
        case .lastYear:
            return calendar.date(byAdding: .year, value: -1, to: trendAnchor) ?? trendAnchor
        }
    }

    private var previousPeriodWorkouts: [Workout] {
        guard let interval = selectedRange.dateInterval(using: calendar, anchor: previousPeriodAnchor) else { return [] }
        return workouts.filter { interval.contains($0.date) }
    }

    private var previousTotalMetricSum: Int {
        previousPeriodWorkouts.reduce(0) { $0 + $1.metricValue(for: activePreferredMetric) }
    }

    private var previousAverageMetricPerMinute: Double? {
        let totalMetric = previousPeriodWorkouts.reduce(0.0) { $0 + Double($1.metricValue(for: activePreferredMetric)) }
        let totalDuration = previousPeriodWorkouts.reduce(0.0) { $0 + $1.duration }
        let minutes = totalDuration / 60.0
        guard minutes > 0 else { return nil }
        return totalMetric / minutes
    }

    private var previousAverageHeartRate: Int? {
        let heartRates = previousPeriodWorkouts.compactMap(\.avgHeartRate)
        guard !heartRates.isEmpty else { return nil }
        return heartRates.reduce(0, +) / heartRates.count
    }

    private var previousTotalDuration: TimeInterval {
        previousPeriodWorkouts.reduce(0.0) { $0 + $1.duration }
    }

    private var previousWorkoutCount: Int {
        previousPeriodWorkouts.count
    }

    // Percentage changes
    private var totalMetricChange: Double? {
        guard previousTotalMetricSum > 0 else { return nil }
        return Double(totalMetricSum - previousTotalMetricSum) / Double(previousTotalMetricSum) * 100
    }

    private var avgPerMinuteChange: Double? {
        guard let current = averageMetricPerMinute,
              let previous = previousAverageMetricPerMinute,
              previous > 0 else { return nil }
        return (current - previous) / previous * 100
    }

    private var avgHeartRateChange: Double? {
        guard let current = averageHeartRate,
              let previous = previousAverageHeartRate,
              previous > 0 else { return nil }
        return Double(current - previous) / Double(previous) * 100
    }

    private var totalDurationChange: Double? {
        guard previousTotalDuration > 0 else { return nil }
        return (totalDuration - previousTotalDuration) / previousTotalDuration * 100
    }

    private var workoutCountChange: Double? {
        guard previousWorkoutCount > 0 else { return nil }
        return Double(workoutCount - previousWorkoutCount) / Double(previousWorkoutCount) * 100
    }

    private var hasEnoughPointData: Bool {
        min(totalPoints.count, perMinutePoints.count) >= 2
    }
    
    private var hasEnoughBucketData: Bool {
        min(totalBuckets.count, perMinuteBuckets.count) >= 2
    }

    private var hasEnoughTotalWorkouts: Bool {
        workouts.count >= 2
    }

    private var usesBuckets: Bool {
        selectedRange.bucketStyle != .perWorkout
    }
    
    private func alignedAnchor(for range: WorkoutTrendRange, base: Date) -> Date {
        switch range {
        case .thisWeek:
            return calendar.startOfDay(for: base)
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: base)?.start ?? base
        case .lastYear:
            return calendar.dateInterval(of: .year, for: base)?.start ?? base
        }
    }

    private func stepBackward() {
        let newAnchor: Date
        switch selectedRange {
        case .thisWeek:
            newAnchor = calendar.date(byAdding: .weekOfYear, value: -1, to: trendAnchor) ?? trendAnchor
        case .thisMonth:
            newAnchor = calendar.date(byAdding: .month, value: -1, to: trendAnchor) ?? trendAnchor
        case .lastYear:
            newAnchor = calendar.date(byAdding: .year, value: -1, to: trendAnchor) ?? trendAnchor
        }
        trendAnchor = alignedAnchor(for: selectedRange, base: newAnchor)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func stepForward() {
        let candidate: Date
        switch selectedRange {
        case .thisWeek:
            candidate = calendar.date(byAdding: .weekOfYear, value: 1, to: trendAnchor) ?? trendAnchor
        case .thisMonth:
            candidate = calendar.date(byAdding: .month, value: 1, to: trendAnchor) ?? trendAnchor
        case .lastYear:
            candidate = calendar.date(byAdding: .year, value: 1, to: trendAnchor) ?? trendAnchor
        }

        if let interval = selectedRange.dateInterval(using: calendar, anchor: candidate),
           interval.start <= Date() {
            trendAnchor = alignedAnchor(for: selectedRange, base: candidate)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                rangePicker
                
                if let description = rangeDescription {
                    HStack {
                        Text(description)
                            .font(.montserratRegular(size: 13))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                        Spacer()
                    }
                }

                // Summary stats (only show when there's data)
                if !filteredWorkouts.isEmpty {
                    summaryStatsView
                }

                if !hasEnoughTotalWorkouts {
                    // User hasn't logged enough workouts overall
                    emptyState
                } else if usesBuckets {
                    // Y (Year) view - bar chart for totals, line charts for trends
                    if filteredWorkouts.isEmpty {
                        noDataInTimeframeState
                    } else {
                        // Steps bar chart with rich tooltip
                        WorkoutTrendBarChartView(
                            title: activePreferredMetric.displayName,
                            unitLabel: activePreferredMetric.unit,
                            buckets: totalBuckets,
                            valueType: .total,
                            bucketStyle: selectedRange.bucketStyle,
                            range: selectedRange,
                            colorScheme: effectiveColorScheme
                        )

                        // Steps per Minute line chart
                        WorkoutTrendBucketLineChartView(
                            title: "\(activePreferredMetric.displayName) per Minute",
                            unitLabel: "\(activePreferredMetric.unit)/min",
                            buckets: perMinuteBuckets,
                            valueType: .perMinute,
                            colorScheme: effectiveColorScheme
                        )

                        // Heart Rate line chart (if data available)
                        if totalBuckets.contains(where: { $0.averageHeartRate != nil }) {
                            WorkoutTrendBucketLineChartView(
                                title: "Average Heart Rate",
                                unitLabel: "bpm",
                                buckets: totalBuckets,
                                valueType: .averageHeartRate,
                                colorScheme: effectiveColorScheme
                            )
                        }

                        // Duration bar chart
                        WorkoutTrendBarChartView(
                            title: "Duration",
                            unitLabel: "min",
                            buckets: totalBuckets,
                            valueType: .duration,
                            bucketStyle: selectedRange.bucketStyle,
                            range: selectedRange,
                            colorScheme: effectiveColorScheme
                        )

                        // Workouts per month bar chart
                        WorkoutTrendBarChartView(
                            title: "Workouts",
                            unitLabel: "",
                            buckets: totalBuckets,
                            valueType: .workoutCount,
                            bucketStyle: selectedRange.bucketStyle,
                            range: selectedRange,
                            colorScheme: effectiveColorScheme
                        )
                    }
                } else {
                    // W/M views - line charts for individual workouts
                    if hasEnoughPointData {
                        WorkoutTrendChartView(
                            title: activePreferredMetric.displayName,
                            unitLabel: activePreferredMetric.unit,
                            points: totalPoints,
                            metricType: .preferredTotal,
                            preferredMetric: activePreferredMetric,
                            colorScheme: effectiveColorScheme
                        )

                        WorkoutTrendChartView(
                            title: "\(activePreferredMetric.displayName) per Minute",
                            unitLabel: "\(activePreferredMetric.unit)/min",
                            points: perMinutePoints,
                            metricType: .preferredPerMinute,
                            preferredMetric: activePreferredMetric,
                            colorScheme: effectiveColorScheme
                        )

                        // Heart Rate line chart (if data available)
                        if heartRatePoints.count >= 2 {
                            WorkoutTrendChartView(
                                title: "Average Heart Rate",
                                unitLabel: "bpm",
                                points: heartRatePoints,
                                metricType: .averageHeartRate,
                                preferredMetric: activePreferredMetric,
                                colorScheme: effectiveColorScheme
                            )
                        }

                        // Duration line chart
                        if durationPoints.count >= 2 {
                            WorkoutTrendChartView(
                                title: "Duration",
                                unitLabel: "min",
                                points: durationPoints,
                                metricType: .duration,
                                preferredMetric: activePreferredMetric,
                                colorScheme: effectiveColorScheme
                            )
                        }
                    } else if filteredWorkouts.isEmpty {
                        noDataInTimeframeState
                    } else {
                        needMoreDataInTimeframeState
                    }
                }
                
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
        }
        .scrollIndicators(.hidden)
        .themedBackground()
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingInfoTooltip = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.accent)
                }
            }
        }
        .sheet(isPresented: $showingInfoTooltip) {
            TooltipView(
                title: "Using Trends",
                content: "Track your workout progress over time with interactive charts.\n\nTap any bar or point to see detailed stats for that period, including totals, averages, and heart rate data.\n\nSwipe left or right within the chart area to navigate between time periods. Use the Week, Month, or Year tabs to change the time range you're viewing."
            )
            .presentationDetents([.fraction(0.62)])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            selectedRange = .thisMonth
            trendAnchor = alignedAnchor(for: .thisMonth, base: Date())
        }
        .onChange(of: selectedRange) { _, _ in
            trendAnchor = alignedAnchor(for: selectedRange, base: Date())
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < -30 {
                        stepForward()
                    } else if value.translation.width > 30 {
                        stepBackward()
                    }
                }
        )
    }
    
    private var rangePicker: some View {
        Picker("Range", selection: $selectedRange) {
            ForEach(WorkoutTrendRange.allCases) { range in
                Text(range.shortTitle)
                    .tag(range)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 320)
    }

    private var summaryStatsView: some View {
        VStack(spacing: 10) {
            // Row 1: Workouts, Duration, Total Metric
            HStack(spacing: 10) {
                statCard(
                    title: "Workouts",
                    value: "\(workoutCount)",
                    unit: "",
                    change: workoutCountChange
                )

                statCard(
                    title: "Duration",
                    value: formatDuration(totalDuration),
                    unit: "",
                    change: totalDurationChange
                )

                statCard(
                    title: "Total \(activePreferredMetric.displayName)",
                    value: formatNumber(totalMetricSum),
                    unit: activePreferredMetric.unit,
                    change: totalMetricChange
                )
            }

            // Row 2: Avg per Minute, Avg Heart Rate
            HStack(spacing: 10) {
                if let avgPerMin = averageMetricPerMinute {
                    statCard(
                        title: "Avg per Min",
                        value: String(format: "%.1f", avgPerMin),
                        unit: "\(activePreferredMetric.unit)/min",
                        change: avgPerMinuteChange
                    )
                }

                if let avgHR = averageHeartRate {
                    statCard(
                        title: "Avg Heart Rate",
                        value: "\(avgHR)",
                        unit: "bpm",
                        change: avgHeartRateChange
                    )
                }
            }
        }
    }

    private func statCard(title: String, value: String, unit: String, change: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.montserratRegular(size: 11))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer()

                if let change = change {
                    changeIndicator(change)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.montserratBold(size: 18))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(unit)
                    .font(.montserratRegular(size: 10))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
        )
    }

    private func changeIndicator(_ change: Double) -> some View {
        let isPositive = change >= 0
        let color: Color = isPositive ? .green : .red
        let arrow = isPositive ? "arrow.up" : "arrow.down"
        let displayValue = abs(change)

        return HStack(spacing: 2) {
            Image(systemName: arrow)
                .font(.system(size: 8, weight: .bold))
            Text(displayValue < 1000 ? String(format: "%.0f%%", displayValue) : "999+%")
                .font(.montserratSemiBold(size: 10))
        }
        .foregroundStyle(color)
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private var rangeDescription: String? {
        guard let interval = selectedRange.dateInterval(using: calendar, anchor: trendAnchor) else { return nil }
        let formatter = DateFormatter()
        switch selectedRange {
        case .thisWeek:
            formatter.dateFormat = "MMM d, yyyy"
            return "\(formatter.string(from: interval.start)) – \(formatter.string(from: interval.end.addingTimeInterval(-1)))"
        case .thisMonth:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: interval.start)
        case .lastYear:
            formatter.dateFormat = "yyyy"
            return formatter.string(from: interval.start)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5))

            Text("Log 2 or more workouts to see your trends.")
                .font(.montserratSemiBold(size: 16))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
        )
    }

    private var isCurrentPeriod: Bool {
        guard let interval = selectedRange.dateInterval(using: calendar, anchor: trendAnchor) else { return false }
        return interval.contains(Date())
    }

    private var periodName: String {
        switch selectedRange {
        case .thisWeek: return "week"
        case .thisMonth: return "month"
        case .lastYear: return "year"
        }
    }

    private var noDataInTimeframeState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5))

            if isCurrentPeriod {
                VStack(spacing: 4) {
                    Text("No workouts logged yet this \(periodName).")
                        .font(.montserratSemiBold(size: 16))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                        .multilineTextAlignment(.center)

                    Text("Log 2 or more workouts to see trends.")
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                        .multilineTextAlignment(.center)
                }
            } else {
                Text("No workouts were logged during this time period.")
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
        )
    }

    private var needMoreDataInTimeframeState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5))

            if isCurrentPeriod {
                Text("Log 1 more workout this \(periodName) to see trends (2+ needed).")
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)
            } else {
                VStack(spacing: 4) {
                    Text("Only 1 workout was logged during this period.")
                        .font(.montserratSemiBold(size: 16))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                        .multilineTextAlignment(.center)

                    Text("2 or more are needed to show trends.")
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
        )
    }
}
