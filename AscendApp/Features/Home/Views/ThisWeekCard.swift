//
//  ThisWeekCard.swift
//  AscendApp
//
//  Refactored from LastSevenDaysSummaryCard
//

import SwiftUI
import SwiftData

struct ThisWeekCard: View {
    let workouts: [Workout]
    var isLoading: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared
    @State private var viewModel = GoalsViewModel()

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var preferredMetric: WorkoutMetric {
        settingsManager.preferredWorkoutMetric
    }

    /// Get the firstWeekday: from goal if exists, otherwise default to Monday (2)
    private var firstWeekday: Int {
        viewModel.activeGoal?.firstWeekday ?? 2
    }

    private var summary: WeekActivitySummary? {
        return WeekActivitySummaryCalculator(
            workouts: workouts,
            metric: preferredMetric,
            firstWeekday: firstWeekday
        ).calculate()
    }

    /// Check if there are any workouts this week
    private var hasWorkoutsThisWeek: Bool {
        guard let summary = summary else { return false }
        return summary.weekWorkoutCount > 0
    }

    var body: some View {
        Group {
            if isLoading {
                loadingStateView
            } else {
                mainContentView
            }
        }
        .padding(20)
        .background(cardBackground)
        .onAppear {
            viewModel.configure(modelContext: modelContext)
            viewModel.loadActiveGoal()
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var mainContentView: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left side: Title + Stats
            VStack(alignment: .leading, spacing: 12) {
                Text("THIS WEEK")
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)

                statsSection
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            // Right side: Chart - spans full height using overlay
            Color.clear
                .frame(width: 160)
                .overlay(alignment: .bottom) {
                    chartSection
                }
        }
    }

    @ViewBuilder
    private var statsSection: some View {
        let summary = self.summary

        VStack(alignment: .leading, spacing: 4) {
            // Session count - PRIMARY identity element
            if let summary = summary, summary.weekWorkoutCount > 0 {
                Text("\(summary.weekWorkoutCount) \(summary.weekWorkoutCount == 1 ? "workout" : "workouts")")
                    .font(.montserratBold(size: 24))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                // Primary metric + duration - supporting context
                Text("\(formatCompactValue(summary.weekTotalValue)) \(preferredMetric.unit) · \(formatCompactDuration(summary.totalDuration))")
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                // Pace comparison (one line, conditional)
                if let paceMessage = summary.paceMessage {
                    Text(paceMessage)
                        .font(.montserratMedium(size: 11))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                        .lineLimit(1)
                }
            } else {
                // Empty state
                Text("No workouts yet")
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)

                Text("Your week resets every \(resetDayName)")
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray.opacity(0.7))
            }
        }
    }

    @ViewBuilder
    private var chartSection: some View {
        let summary = self.summary

        MiniWeekBarChart(
            data: summary?.dailyBars ?? emptyChartBars,
            hasData: hasWorkoutsThisWeek
        )
    }

    /// Generate empty chart bars when there's no summary
    private var emptyChartBars: [DailyActivityData] {
        var calendar = Calendar.current
        calendar.firstWeekday = firstWeekday

        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: Date()) else {
            return []
        }

        var bars: [DailyActivityData] = []
        let today = calendar.startOfDay(for: Date())

        for dayOffset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: weekInterval.start) else { continue }
            let isFuture = day > today
            bars.append(DailyActivityData(
                date: day,
                value: 0,
                label: dayLabel(for: day, calendar: calendar),
                isToday: calendar.isDate(day, inSameDayAs: today),
                isFuture: isFuture
            ))
        }
        return bars
    }

    // MARK: - Loading State

    private var loadingStateView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(placeholderPrimaryColor)
                        .frame(width: 120, height: 18)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(placeholderSecondaryColor)
                        .frame(width: 140, height: 14)
                }

                Spacer()

                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { index in
                        let heights: [CGFloat] = [30, 50, 70, 55, 45, 65, 80]
                        RoundedRectangle(cornerRadius: 3)
                            .fill(placeholderSecondaryColor)
                            .frame(width: 12, height: heights[index % heights.count])
                    }
                }
                .frame(width: 140, height: 80)
            }

            Rectangle()
                .fill(placeholderSecondaryColor)
                .frame(height: 1)

            RoundedRectangle(cornerRadius: 6)
                .fill(placeholderSecondaryColor)
                .frame(width: 180, height: 14)
        }
        .redacted(reason: .placeholder)
    }

    private var placeholderPrimaryColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.15) : .gray.opacity(0.1)
    }

    private var placeholderSecondaryColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.08)
    }

    // MARK: - Helpers

    private var resetDayName: String {
        let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let index = (firstWeekday - 1) % 7
        return dayNames[index]
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// Compact duration for glanceable display (e.g., "25.4h" instead of "25h 25m")
    private func formatCompactDuration(_ duration: TimeInterval) -> String {
        let totalHours = duration / 3600
        if totalHours >= 1 {
            // Show decimal for partial hours (1.5h for 1h 30m)
            let rounded = (totalHours * 10).rounded() / 10
            if rounded == rounded.rounded() {
                return "\(Int(rounded))h"
            } else {
                return "\(rounded.formatted(.number.precision(.fractionLength(1))))h"
            }
        } else {
            let minutes = Int(duration / 60)
            return "\(minutes)m"
        }
    }

    /// Compact value formatting (e.g., "107.5k" instead of "107,500")
    private func formatCompactValue(_ value: Int) -> String {
        if value >= 1000 {
            let thousands = Double(value) / 1000.0
            // Always show one decimal, drop if .0
            let rounded = (thousands * 10).rounded() / 10
            if rounded == rounded.rounded() {
                return "\(Int(rounded))k"
            } else {
                return "\(rounded.formatted(.number.precision(.fractionLength(1))))k"
            }
        } else {
            return "\(value)"
        }
    }

    private func formatGoalProgress(current: Int, target: Int, metric: GoalMetric) -> String {
        if metric == .duration {
            return "\(formatDurationMinutes(current)) / \(formatDurationMinutes(target))"
        }
        let unit = target == 1 ? metric.unitSingular : metric.unit
        return "\(current.formatted()) / \(target.formatted()) \(unit)"
    }

    private func formatRemaining(_ remaining: Int, metric: GoalMetric) -> String {
        if metric == .duration {
            return formatDurationMinutes(remaining)
        }
        return remaining.formatted()
    }

    private func formatDurationMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(mins)m"
        }
    }

    private func dayLabel(for date: Date, calendar: Calendar) -> String {
        let weekday = calendar.component(.weekday, from: date)
        if weekday - 1 >= 0 && weekday - 1 < calendar.shortWeekdaySymbols.count {
            return String(calendar.shortWeekdaySymbols[weekday - 1].prefix(1)).uppercased()
        }
        return "?"
    }
}

// MARK: - Mini Week Bar Chart

private struct MiniWeekBarChart: View {
    let data: [DailyActivityData]
    let hasData: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var maxValue: Double {
        Double(data.map(\.value).max() ?? 0)
    }

    private let labelHeight: CGFloat = 14 // Space for day labels

    var body: some View {
        GeometryReader { geometry in
            let availableBarHeight = geometry.size.height - labelHeight - 5 // 5 is VStack spacing
            let safeMax = max(maxValue, 1)

            VStack(spacing: 5) {
                // Bars area - grows upward from baseline
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(data) { day in
                        RoundedRectangle(cornerRadius: 5)
                            .fill(barFill(for: day))
                            .frame(width: 18, height: barHeight(for: day, availableHeight: availableBarHeight, safeMax: safeMax))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)

                // Day labels at bottom
                HStack(spacing: 6) {
                    ForEach(data) { day in
                        Text(day.label)
                            .font(.montserratMedium(size: 9))
                            .foregroundStyle(labelColor(for: day))
                            .frame(width: 18)
                    }
                }
                .frame(height: labelHeight)
            }
        }
    }

    private func barHeight(for day: DailyActivityData, availableHeight: CGFloat, safeMax: Double) -> CGFloat {
        if day.isFuture || day.value == 0 {
            return 4 // Minimum height for empty/future bars
        }
        let ratio = Double(day.value) / safeMax
        return max(8, availableHeight * CGFloat(ratio))
    }

    private var barColor: Color {
        .accentColor
    }

    private var emptyBarColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.15) : .gray.opacity(0.15)
    }

    private func labelColor(for day: DailyActivityData) -> Color {
        if day.isFuture {
            return effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.4)
        }
        return effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray
    }

    private func barFill(for day: DailyActivityData) -> Color {
        if day.isFuture || day.value == 0 {
            return emptyBarColor
        }
        return barColor
    }
}

// MARK: - Data Models

private struct WeekActivitySummary {
    let dailyBars: [DailyActivityData]
    let weekTotalValue: Int
    let weekWorkoutCount: Int
    let totalDuration: TimeInterval
    let weekInterval: DateInterval
    let typicalWeekAvgValue: Int
    let typicalWeekAvgWorkouts: Int
    let hasTypicalWeekData: Bool

    /// Calculate how many days have elapsed in the current week (1-7)
    private var daysElapsedInWeek: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekStart = calendar.startOfDay(for: weekInterval.start)
        let days = calendar.dateComponents([.day], from: weekStart, to: today).day ?? 0
        return min(max(days + 1, 1), 7) // 1-7
    }

    /// Expected sessions by this point in the week
    var expectedSessionsByNow: Int {
        guard hasTypicalWeekData, typicalWeekAvgWorkouts > 0 else { return 0 }
        let expected = Double(typicalWeekAvgWorkouts) * Double(daysElapsedInWeek) / 7.0
        return Int(ceil(expected))
    }

    /// Whether user is ahead of their usual pace
    var isAheadOfPace: Bool {
        guard hasTypicalWeekData else { return false }
        return weekWorkoutCount >= expectedSessionsByNow
    }

    /// The pace comparison message (only shown if hasTypicalWeekData)
    var paceMessage: String? {
        guard hasTypicalWeekData, typicalWeekAvgWorkouts > 0 else { return nil }

        if isAheadOfPace {
            return "Ahead of your usual pace"
        } else {
            let typical = expectedSessionsByNow
            return "\(typical) \(typical == 1 ? "session" : "sessions") typical by now"
        }
    }

    var preferredDefaultDay: DailyActivityData? {
        // Prefer today if it has data
        if let today = dailyBars.first(where: { Calendar.current.isDateInToday($0.date) && $0.value > 0 }) {
            return today
        }
        // Otherwise, find the most recent day with data
        return dailyBars.reversed().first(where: { $0.value > 0 && !$0.isFuture })
    }

    var preferredDefaultDate: Date? {
        preferredDefaultDay?.date
    }
}

private struct DailyActivityData: Identifiable {
    let date: Date
    let value: Int
    let label: String
    let isToday: Bool
    let isFuture: Bool

    var id: Date { date }
}

// MARK: - Calculator

private struct WeekActivitySummaryCalculator {
    let workouts: [Workout]
    let metric: WorkoutMetric
    let firstWeekday: Int

    func calculate(referenceDate: Date = Date()) -> WeekActivitySummary {
        var calendar = Calendar.current
        calendar.firstWeekday = firstWeekday

        let today = calendar.startOfDay(for: referenceDate)

        // Get current week interval
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: today) else {
            return emptyResult(calendar: calendar, today: today)
        }

        // Get one year ago for typical week calculation
        guard let startYear = calendar.date(byAdding: .year, value: -1, to: today) else {
            return emptyResult(calendar: calendar, today: today)
        }

        // Filter workouts to past year (up to today, not future)
        let filteredWorkouts = workouts.filter { workout in
            let day = calendar.startOfDay(for: workout.date)
            return day >= startYear && day <= today
        }

        // Build daily values map
        var dailyValues: [Date: (value: Int, duration: TimeInterval)] = [:]
        for workout in filteredWorkouts {
            let day = calendar.startOfDay(for: workout.date)
            let value = workout.metricValue(for: metric)
            let existing = dailyValues[day] ?? (0, 0)
            dailyValues[day] = (existing.value + value, existing.duration + workout.duration)
        }

        // Build daily bars for the current week (Mon-Sun or Sun-Sat based on firstWeekday)
        var dailyBars: [DailyActivityData] = []
        for dayOffset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: weekInterval.start) else { continue }
            let dayStart = calendar.startOfDay(for: day)
            let isFuture = dayStart > today
            let data = dailyValues[dayStart]
            dailyBars.append(DailyActivityData(
                date: dayStart,
                value: isFuture ? 0 : (data?.value ?? 0),
                label: dayLabel(for: dayStart, calendar: calendar),
                isToday: calendar.isDate(dayStart, inSameDayAs: today),
                isFuture: isFuture
            ))
        }

        // Current week totals (only up to today)
        let weekWorkouts = filteredWorkouts.filter { workout in
            weekInterval.contains(workout.date)
        }
        let weekTotalValue = weekWorkouts.reduce(0) { $0 + $1.metricValue(for: metric) }
        let weekWorkoutCount = weekWorkouts.count
        let totalDuration = weekWorkouts.reduce(0.0) { $0 + $1.duration }

        // Typical week calculation (past year excluding current week)
        let typicalEnd = weekInterval.start.addingTimeInterval(-1) // End of last week
        let typicalPeriodWorkouts = filteredWorkouts.filter { workout in
            let day = calendar.startOfDay(for: workout.date)
            return day >= startYear && day <= typicalEnd
        }

        // Group by week
        var weeklyTotals: [Int: (value: Int, workouts: Int)] = [:]
        for workout in typicalPeriodWorkouts {
            let weekOfYear = calendar.component(.weekOfYear, from: workout.date)
            let year = calendar.component(.yearForWeekOfYear, from: workout.date)
            let weekKey = year * 100 + weekOfYear
            let value = workout.metricValue(for: metric)
            let existing = weeklyTotals[weekKey] ?? (0, 0)
            weeklyTotals[weekKey] = (existing.value + value, existing.workouts + 1)
        }

        let weeksWithActivity = weeklyTotals.count
        let typicalPeriodTotal = weeklyTotals.values.reduce(0) { $0 + $1.value }
        let typicalPeriodWorkoutCount = weeklyTotals.values.reduce(0) { $0 + $1.workouts }
        let hasTypicalWeekData = weeksWithActivity >= 1

        let typicalWeekAvgValue: Int
        let typicalWeekAvgWorkouts: Int

        if hasTypicalWeekData {
            typicalWeekAvgValue = Int((Double(typicalPeriodTotal) / Double(weeksWithActivity)).rounded(.toNearestOrAwayFromZero))
            typicalWeekAvgWorkouts = Int((Double(typicalPeriodWorkoutCount) / Double(weeksWithActivity)).rounded(.toNearestOrAwayFromZero))
        } else {
            typicalWeekAvgValue = 0
            typicalWeekAvgWorkouts = 0
        }

        return WeekActivitySummary(
            dailyBars: dailyBars,
            weekTotalValue: weekTotalValue,
            weekWorkoutCount: weekWorkoutCount,
            totalDuration: totalDuration,
            weekInterval: weekInterval,
            typicalWeekAvgValue: typicalWeekAvgValue,
            typicalWeekAvgWorkouts: typicalWeekAvgWorkouts,
            hasTypicalWeekData: hasTypicalWeekData
        )
    }

    private func emptyResult(calendar: Calendar, today: Date) -> WeekActivitySummary {
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: today) ?? DateInterval(start: today, duration: 7 * 24 * 60 * 60)

        var dailyBars: [DailyActivityData] = []
        for dayOffset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: weekInterval.start) else { continue }
            let isFuture = day > today
            dailyBars.append(DailyActivityData(
                date: day,
                value: 0,
                label: dayLabel(for: day, calendar: calendar),
                isToday: calendar.isDate(day, inSameDayAs: today),
                isFuture: isFuture
            ))
        }

        return WeekActivitySummary(
            dailyBars: dailyBars,
            weekTotalValue: 0,
            weekWorkoutCount: 0,
            totalDuration: 0,
            weekInterval: weekInterval,
            typicalWeekAvgValue: 0,
            typicalWeekAvgWorkouts: 0,
            hasTypicalWeekData: false
        )
    }

    private func dayLabel(for date: Date, calendar: Calendar) -> String {
        let weekday = calendar.component(.weekday, from: date)
        if weekday - 1 >= 0 && weekday - 1 < calendar.shortWeekdaySymbols.count {
            return String(calendar.shortWeekdaySymbols[weekday - 1].prefix(1)).uppercased()
        }
        return "?"
    }
}

// MARK: - Weekly Goal Card

struct WeeklyGoalCard: View {
    let workouts: [Workout]
    @Binding var showGoalsSheet: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var themeManager = ThemeManager.shared
    @State private var viewModel = GoalsViewModel()

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let goal = viewModel.activeGoal,
               let progress = viewModel.progress {
                // Has goal state
                goalContent(goal: goal, progress: progress)
            } else {
                // Empty state
                emptyStateContent
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .onAppear {
            viewModel.configure(modelContext: modelContext)
            viewModel.loadActiveGoal()
            viewModel.calculateProgress(from: workouts)
        }
        .onChange(of: workouts.count) { _, _ in
            viewModel.calculateProgress(from: workouts)
        }
        .onChange(of: showGoalsSheet) { oldValue, newValue in
            if oldValue && !newValue {
                viewModel.loadActiveGoal()
                viewModel.calculateProgress(from: workouts)
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
            )
    }

    @ViewBuilder
    private func goalContent(goal: Goal, progress: GoalProgress) -> some View {
        let isComplete = progress.current >= progress.target

        // Title row
        HStack {
            Text("WEEKLY GOAL")
                .font(.montserratMedium(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)

            Spacer()

            Button(action: { showGoalsSheet = true }) {
                Text("Edit")
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(.accent)
            }
            .buttonStyle(.plain)
        }

        if isComplete {
            // Complete state - show achievement + overflow (subdued)
            HStack(spacing: 6) {
                Text(formatTarget(target: progress.target, metric: goal.metric))
                    .font(.montserratMedium(size: 18))
                    .foregroundStyle(.accent)

                Text("✓")
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(.accent.opacity(0.7))
            }

            // Overflow amount - small and muted
            let overflow = progress.current - progress.target
            if overflow > 0 {
                Text("+\(formatOverflow(overflow, metric: goal.metric)) over goal")
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray.opacity(0.7))
            }
        } else {
            // In progress state - constraint, not trophy
            Text(formatTarget(target: progress.target, metric: goal.metric))
                .font(.montserratMedium(size: 18))
                .foregroundStyle(.accent)

            Text("\(progressPercentage(progress))% complete")
                .font(.montserratRegular(size: 12))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray.opacity(0.7))
        }

        // Progress bar
        GoalProgressBar(
            current: progress.current,
            target: progress.target,
            metric: goal.metric
        )
    }

    @ViewBuilder
    private var emptyStateContent: some View {
        Text("WEEKLY GOAL")
            .font(.montserratMedium(size: 14))
            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)

        Text("Set a weekly target to track your progress.")
            .font(.montserratRegular(size: 14))
            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)

        Button(action: { showGoalsSheet = true }) {
            HStack(spacing: 6) {
                Text("Set a goal")
                    .font(.montserratMedium(size: 14))
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.accent)
        }
        .buttonStyle(.plain)
    }

    private func progressPercentage(_ progress: GoalProgress) -> Int {
        guard progress.target > 0 else { return 0 }
        return min(Int((Double(progress.current) / Double(progress.target)) * 100), 100)
    }

    private func formatTarget(target: Int, metric: GoalMetric) -> String {
        if metric == .duration {
            return formatDurationMinutes(target)
        }
        let unit = target == 1 ? metric.unitSingular : metric.unit
        return "\(target.formatted()) \(unit)"
    }

    private func formatRemaining(remaining: Int, metric: GoalMetric) -> String {
        if remaining <= 0 {
            return "0"
        }
        if metric == .duration {
            return formatDurationMinutes(remaining)
        }
        return remaining.formatted()
    }

    private func formatOverflow(_ overflow: Int, metric: GoalMetric) -> String {
        if metric == .duration {
            return formatDurationMinutes(overflow)
        }
        let unit = overflow == 1 ? metric.unitSingular : metric.unit
        return "\(overflow) \(unit)"
    }

    private func formatDurationMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }
}

// MARK: - Goal Progress Bar

private struct GoalProgressBar: View {
    let current: Int
    let target: Int
    let metric: GoalMetric

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    /// For workouts, use target as segment count
    /// For other metrics, use a fixed 10 segments
    private var segmentCount: Int {
        if metric == .workouts {
            return max(target, 1)
        }
        return 10
    }

    private var filledSegments: Int {
        guard target > 0 else { return 0 }
        if metric == .workouts {
            return min(current, target)
        }
        let progress = Double(current) / Double(target)
        return min(Int(ceil(progress * Double(segmentCount))), segmentCount)
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<segmentCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < filledSegments ? Color.accentColor.opacity(0.8) : emptyColor)
                    .frame(height: 6)
            }
        }
    }

    private var emptyColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.15) : .gray.opacity(0.2)
    }
}

// MARK: - Preview

#Preview("This Week - With Data") {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())

    let sampleWorkouts: [Workout] = (0..<8).map { index in
        let dayOffset = Int.random(in: 0...6)
        let steps = Int.random(in: 800...3500)
        let date = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
        return Workout(
            name: "Stair Session",
            date: date,
            duration: TimeInterval(Int.random(in: 1200...5400)),
            steps: steps,
            floors: Workout.stepsToFloors(steps, stepsPerFloor: 16),
            stepsPerFloor: 16,
            notes: "Sample"
        )
    }

    return ThisWeekCard(workouts: sampleWorkouts)
        .padding(20)
}

#Preview("This Week - Empty") {
    ThisWeekCard(workouts: [])
        .padding(20)
}

#Preview("Weekly Goal Card") {
    WeeklyGoalCard(workouts: [], showGoalsSheet: .constant(false))
        .padding(20)
}
