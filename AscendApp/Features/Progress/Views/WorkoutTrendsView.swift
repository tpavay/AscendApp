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
        WorkoutTrendsBuilder.trendBuckets(from: filteredWorkouts, preferredMetric: activePreferredMetric, range: selectedRange, calendar: calendar, anchor: initialMonth)
    }
    
    private var perMinuteBuckets: [WorkoutTrendBucket] {
        WorkoutTrendsBuilder.trendBuckets(from: filteredWorkouts, preferredMetric: activePreferredMetric, range: selectedRange, calendar: calendar, anchor: initialMonth)
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
    
    private var usesBuckets: Bool {
        selectedRange.bucketStyle != .perWorkout
    }
    
    private func alignedAnchor(for range: WorkoutTrendRange, base: Date) -> Date {
        switch range {
        case .thisWeek:
            return calendar.startOfDay(for: base)
        case .thisMonth, .lastSixMonths, .lastYear:
            return calendar.dateInterval(of: .month, for: base)?.start ?? base
        }
    }
    
    private func stepBackward() {
        let newAnchor: Date
        switch selectedRange {
        case .thisWeek:
            newAnchor = calendar.date(byAdding: .weekOfYear, value: -1, to: trendAnchor) ?? trendAnchor
        case .thisMonth:
            newAnchor = calendar.date(byAdding: .month, value: -1, to: trendAnchor) ?? trendAnchor
        case .lastSixMonths:
            newAnchor = calendar.date(byAdding: .month, value: -6, to: trendAnchor) ?? trendAnchor
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
        case .lastSixMonths:
            candidate = calendar.date(byAdding: .month, value: 6, to: trendAnchor) ?? trendAnchor
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
                
                if usesBuckets {
                    if hasEnoughBucketData {
                        WorkoutTrendBarChartView(
                            title: activePreferredMetric.displayName,
                            unitLabel: activePreferredMetric.unit,
                            buckets: totalBuckets,
                            valueType: .total,
                            bucketStyle: selectedRange.bucketStyle,
                            range: selectedRange,
                            colorScheme: effectiveColorScheme
                        )
                        
                        WorkoutTrendBarChartView(
                            title: "\(activePreferredMetric.displayName) per Minute",
                            unitLabel: "\(activePreferredMetric.unit)/min",
                            buckets: perMinuteBuckets,
                            valueType: .perMinute,
                            bucketStyle: selectedRange.bucketStyle,
                            range: selectedRange,
                            colorScheme: effectiveColorScheme
                        )
                    } else {
                        emptyState
                    }
                } else {
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
                    } else {
                        emptyState
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
        formatter.dateFormat = "MMM d, yyyy"
        switch selectedRange {
        case .thisWeek:
            return "\(formatter.string(from: interval.start)) – \(formatter.string(from: interval.end.addingTimeInterval(-1)))"
        case .thisMonth:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: interval.start)
        case .lastSixMonths:
            formatter.dateFormat = "MMM yyyy"
            return "\(formatter.string(from: interval.start)) – \(formatter.string(from: interval.end.addingTimeInterval(-1)))"
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
}
