//
//  LastSevenDaysSummaryCard.swift
//  AscendApp
//
//  Created by ChatGPT on 3/15/24.
//

import SwiftUI

struct LastSevenDaysSummaryCard: View {
    let workouts: [Workout]
    var isLoading: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared
    @State private var selectedDate: Date?
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    private var preferredMetric: WorkoutMetric {
        settingsManager.preferredWorkoutMetric
    }
    
    private var summary: ClimbActivitySummary? {
        guard !workouts.isEmpty else { return nil }
        return ClimbActivitySummaryCalculator(workouts: workouts, metric: preferredMetric).calculate()
    }
    
    var body: some View {
        Group {
            if isLoading {
                loadingStateView
            } else if summary == nil {
                emptyStateView
            } else if let summary {
                contentView(summary)
            }
        }
        .padding(20)
        .background(cardBackground)
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
            )
    }
    
    private var loadingStateView: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(placeholderPrimaryColor)
                .frame(height: 22)
                .redacted(reason: .placeholder)
            
            RoundedRectangle(cornerRadius: 8)
                .fill(placeholderSecondaryColor)
                .frame(height: 18)
                .redacted(reason: .placeholder)
            
            HStack(spacing: 12) {
                ForEach(0..<7, id: \.self) { index in
                    let heights: [CGFloat] = [30, 50, 70, 55, 45, 65, 80]
                    RoundedRectangle(cornerRadius: 4)
                        .fill(placeholderSecondaryColor)
                        .frame(width: 18, height: heights[index % heights.count])
                        .redacted(reason: .placeholder)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)
        }
    }

    private var placeholderPrimaryColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.15) : .gray.opacity(0.1)
    }
    
    private var placeholderSecondaryColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.08)
    }
    
    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No stair workouts yet.")
                .font(.montserratMedium(size: 16))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.85) : .black)
            
            Text("Your weekly summary will appear here after your first workout.")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func contentView(_ summary: ClimbActivitySummary) -> some View {
        let selectedDay = selectedDay(in: summary)
        
        let activeDate = selectedDate ?? summary.preferredDefaultDate
        
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(summary.last7TotalValue.formatted()) \(preferredMetric.unit) • \(summary.last7WorkoutCount.formatted()) \(summary.last7WorkoutCount == 1 ? "workout" : "workouts")")
                    .font(.montserratBold(size: 22))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                if summary.prior7TotalValue > 0, let percentChange = summary.percentChange {
                    HStack(spacing: 8) {
                        Text("Change vs prior 7 days")
                            .font(.montserratSemiBold(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.85) : .black)
                        
                        Text(formattedPercentChange(percentChange))
                            .font(.montserratBold(size: 15))
                            .foregroundStyle(percentChangeColor(percentChange))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(percentChangeBackground(percentChange))
                            .clipShape(Capsule())
                    }
                } else {
                    Text(summary.secondaryLine(for: preferredMetric))
                        .font(.montserratSemiBold(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                }
            }
            
            MiniClimbBarChart(
                data: summary.dailyBars,
                highlightedDate: activeDate
            ) { date in
                if let selectedDate,
                   Calendar.current.isDate(selectedDate, inSameDayAs: date) {
                    return
                }
                selectedDate = date
            }
            
            if let selectedDay {
                Text("\(detailedLabel(for: selectedDay.date)): \(selectedDay.value.formatted()) \(preferredMetric.unit)")
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.85) : .gray)
                    .transition(.opacity)
            }
        }
        .onAppear {
            ensureSelectionExists(in: summary)
        }
        .onChange(of: summary.dailyBars.map(\.date)) { _, newDates in
            guard !newDates.isEmpty else {
                selectedDate = nil
                return
            }
            
            if let currentSelection = selectedDate,
               newDates.contains(where: { Calendar.current.isDate($0, inSameDayAs: currentSelection) }) {
                return
            }
            
            selectedDate = summary.preferredDefaultDate
        }
    }
    
    private func selectedDay(in summary: ClimbActivitySummary) -> DailyClimbData? {
        if let selectedDate,
           let match = summary.dailyBars.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) {
            return match
        }
        return summary.preferredDefaultDay
    }
    
    private func ensureSelectionExists(in summary: ClimbActivitySummary) {
        guard selectedDate == nil else { return }
        selectedDate = summary.preferredDefaultDate
    }
    
    private func detailedLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
    
    private func formattedPercentChange(_ percentChange: Int) -> String {
        percentChange > 0 ? "+\(percentChange)%" : "\(percentChange)%"
    }
    
    private func percentChangeColor(_ percentChange: Int) -> Color {
        if percentChange > 0 {
            return .green
        } else if percentChange < 0 {
            return .red
        }
        return effectiveColorScheme == .dark ? .white.opacity(0.85) : .gray
    }
    
    private func percentChangeBackground(_ percentChange: Int) -> Color {
        percentChangeColor(percentChange).opacity(effectiveColorScheme == .dark ? 0.28 : 0.12)
    }
}

// MARK: - Chart

private struct MiniClimbBarChart: View {
    let data: [DailyClimbData]
    let highlightedDate: Date?
    let onSelect: (Date) -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    private let calendar = Calendar.current
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    private var maxValue: Double {
        Double(data.map(\.value).max() ?? 0)
    }
    
    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geometry in
                let chartHeight = geometry.size.height
                let safeMax = max(maxValue, 1)
                
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(data) { day in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                onSelect(day.date)
                            }
                        } label: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(barFill(for: day))
                                .frame(height: barHeight(value: Double(day.value), chartHeight: chartHeight, safeMax: safeMax))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 100)
            
            HStack {
                ForEach(data) { day in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            onSelect(day.date)
                        }
                    } label: {
                        Text(day.label)
                            .font(.montserratMedium(size: 11))
                            .foregroundStyle(labelColor(for: day))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var barColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.35) : .gray.opacity(0.35)
    }
    
    private func labelColor(for day: DailyClimbData) -> Color {
        if isHighlighted(day) {
            return effectiveColorScheme == .dark ? .white : .black
        }
        return effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray
    }
    
    private func barFill(for day: DailyClimbData) -> Color {
        if isHighlighted(day) {
            return .accentColor
        }
        return barColor
    }
    
    private func barHeight(value: Double, chartHeight: CGFloat, safeMax: Double) -> CGFloat {
        guard safeMax > 0 else { return 4 }
        let clampedValue = min(value, safeMax)
        let ratio = clampedValue / safeMax
        let minHeight: CGFloat = value == 0 ? 2 : 8
        return max(minHeight, chartHeight * CGFloat(ratio))
    }
    
    private func isHighlighted(_ day: DailyClimbData) -> Bool {
        guard let highlightedDate else { return false }
        return calendar.isDate(highlightedDate, inSameDayAs: day.date)
    }
}

// MARK: - Summary Calculation

private struct ClimbActivitySummary {
    let dailyBars: [DailyClimbData]
    let last7TotalValue: Int
    let last7WorkoutCount: Int
    let prior7TotalValue: Int
    let percentChange: Int?
    let weeklyAverageValuePerWorkout: Int
    
    func secondaryLine(for metric: WorkoutMetric) -> String {
        if prior7TotalValue > 0, let percentChange {
            let sign = percentChange > 0 ? "+" : ""
            return "\(sign)\(percentChange)% vs prior 7 days"
        } else {
            return "Weekly average: \(weeklyAverageValuePerWorkout.formatted()) \(metric.unit)/workout"
        }
    }
    
    var preferredDefaultDay: DailyClimbData? {
        if let today = dailyBars.first(where: { Calendar.current.isDateInToday($0.date) }) {
            return today
        }
        return dailyBars.last
    }
    
    var preferredDefaultDate: Date? {
        preferredDefaultDay?.date
    }
}

private struct DailyClimbData: Identifiable {
    let date: Date
    let value: Int
    let label: String
    let isToday: Bool
    
    var id: Date { date }
}

private struct ClimbActivitySummaryCalculator {
    let workouts: [Workout]
    let metric: WorkoutMetric
    private let calendar = Calendar.current
    
    func calculate(referenceDate: Date = Date()) -> ClimbActivitySummary {
        let today = calendar.startOfDay(for: referenceDate)
        guard let start28 = calendar.date(byAdding: .day, value: -27, to: today) else {
            return ClimbActivitySummary(
                dailyBars: [],
                last7TotalValue: 0,
                last7WorkoutCount: 0,
                prior7TotalValue: 0,
                percentChange: nil,
                weeklyAverageValuePerWorkout: 0
            )
        }
        
        var dailyValues: [Date: Int] = [:]
        
        let filteredWorkouts = workouts.filter { workout in
            let day = calendar.startOfDay(for: workout.date)
            return day >= start28 && day <= today
        }
        
        for workout in filteredWorkouts {
            let day = calendar.startOfDay(for: workout.date)
            let value = workout.metricValue(for: metric)
            dailyValues[day, default: 0] += value
        }
        
        let last7Start = calendar.date(byAdding: .day, value: -6, to: today)!
        let prior7Start = calendar.date(byAdding: .day, value: -13, to: today)!
        let prior7End = calendar.date(byAdding: .day, value: -7, to: today)!
        
        var dailyBars: [DailyClimbData] = []
        for offset in stride(from: -6, through: 0, by: 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let value = dailyValues[day] ?? 0
            dailyBars.append(
                DailyClimbData(
                    date: day,
                    value: value,
                    label: dayLabel(for: day),
                    isToday: calendar.isDate(day, inSameDayAs: today)
                )
            )
        }
        
        let last7Total = dailyValues
            .filter { $0.key >= last7Start }
            .reduce(0) { $0 + $1.value }
        
        let prior7Total = dailyValues
            .filter { $0.key >= prior7Start && $0.key <= prior7End }
            .reduce(0) { $0 + $1.value }
        
        let last7WorkoutCount = filteredWorkouts.filter { workout in
            let day = calendar.startOfDay(for: workout.date)
            return day >= last7Start
        }.count
        
        let percentChange: Int?
        if prior7Total > 0 {
            let change = Double(last7Total - prior7Total) / Double(prior7Total) * 100
            percentChange = Int(change.rounded(.toNearestOrAwayFromZero))
        } else {
            percentChange = nil
        }
        
        let averageValuePerWorkout: Int
        if last7WorkoutCount > 0 {
            averageValuePerWorkout = Int((Double(last7Total) / Double(last7WorkoutCount)).rounded(.toNearestOrAwayFromZero))
        } else {
            averageValuePerWorkout = 0
        }
        
        return ClimbActivitySummary(
            dailyBars: dailyBars,
            last7TotalValue: last7Total,
            last7WorkoutCount: last7WorkoutCount,
            prior7TotalValue: prior7Total,
            percentChange: percentChange,
            weeklyAverageValuePerWorkout: averageValuePerWorkout
        )
    }
    
    private func dayLabel(for date: Date) -> String {
        let weekday = calendar.component(.weekday, from: date)
        if weekday - 1 >= 0 && weekday - 1 < calendar.shortWeekdaySymbols.count {
            return String(calendar.shortWeekdaySymbols[weekday - 1].prefix(1)).uppercased()
        }
        return "?"
    }
}

#Preview {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    
    let sampleWorkouts: [Workout] = (0..<12).map { index in
        let dayOffset = Int.random(in: 0...20)
        let steps = Int.random(in: 400...2800)
        let date = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
        return Workout(
            name: "Stair Session",
            date: date,
            duration: 1800,
            steps: steps,
            floors: Workout.stepsToFloors(steps, stepsPerFloor: 16),
            stepsPerFloor: 16,
            notes: "Sample"
        )
    }
    
    return VStack(spacing: 16) {
        LastSevenDaysSummaryCard(workouts: sampleWorkouts)
        LastSevenDaysSummaryCard(workouts: [], isLoading: false)
        LastSevenDaysSummaryCard(workouts: sampleWorkouts, isLoading: true)
    }
    .padding()
    .background(Color.black.opacity(0.05))
}
