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
