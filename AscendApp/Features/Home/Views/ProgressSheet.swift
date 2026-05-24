//
//  ProgressSheet.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/28/25.
//

import SwiftData
import SwiftUI

struct ProgressSheet: View {
    let workouts: [Workout]

    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \BestEffortCacheEntry.sortKey) private var bestEffortCacheEntries: [BestEffortCacheEntry]
    @State private var themeManager = ThemeManager.shared
    @State private var selectedDate = Date()
    @State private var selectedCalendarDay: CalendarDay?

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var calendar: Calendar {
        Calendar.current
    }

    private var monthYearFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM, yyyy"
        return formatter
    }

    private var shortMonthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }

    private var selectedMonthInterval: DateInterval {
        calendar.dateInterval(of: .month, for: selectedDate) ?? DateInterval(start: selectedDate, duration: 0)
    }

    private var previousMonthInterval: DateInterval? {
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: selectedDate) else {
            return nil
        }

        return calendar.dateInterval(of: .month, for: previousMonth)
    }

    private var selectedMonthContainsToday: Bool {
        calendar.isDate(selectedDate, equalTo: Date(), toGranularity: .month)
    }

    private var previousComparisonInterval: DateInterval? {
        guard let previousMonthInterval else { return nil }

        guard selectedMonthContainsToday else {
            return previousMonthInterval
        }

        let currentDay = calendar.component(.day, from: Date())
        let previousMonthDays = calendar.range(of: .day, in: .month, for: previousMonthInterval.start)?.count ?? currentDay
        let comparisonDayCount = min(currentDay, previousMonthDays)
        let end = calendar.date(byAdding: .day, value: comparisonDayCount, to: previousMonthInterval.start) ?? previousMonthInterval.end
        return DateInterval(start: previousMonthInterval.start, end: min(end, previousMonthInterval.end))
    }

    private var previousComparisonLabel: String {
        guard let previousComparisonInterval else {
            return "previous month"
        }

        if selectedMonthContainsToday {
            let inclusiveEnd = calendar.date(byAdding: .day, value: -1, to: previousComparisonInterval.end) ?? previousComparisonInterval.start
            let endDay = calendar.component(.day, from: inclusiveEnd)
            return "\(shortMonthFormatter.string(from: previousComparisonInterval.start)) 1-\(endDay)"
        }

        return shortMonthFormatter.string(from: previousComparisonInterval.start)
    }

    private var canGoToNextMonth: Bool {
        let nextMonthDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
        return calendar.compare(nextMonthDate, to: Date(), toGranularity: .month) != .orderedDescending
    }

    private var weeklyStreak: Int {
        Workout.calculateWeeklyStreak(from: workouts)
    }

    private var longestWeeklyStreak: Int {
        Workout.calculateLongestWeeklyStreak(from: workouts)
    }

    private var currentMonthWorkouts: [Workout] {
        workouts(in: selectedMonthInterval)
    }

    private var previousMonthWorkouts: [Workout] {
        guard let previousComparisonInterval else { return [] }
        return workouts(in: previousComparisonInterval)
    }

    private var totalStepsThisMonth: Int {
        currentMonthWorkouts.reduce(0) { $0 + $1.steps }
    }

    private var previousMonthStepTotal: Int {
        previousMonthWorkouts.reduce(0) { $0 + $1.steps }
    }

    private var totalDurationThisMonth: TimeInterval {
        currentMonthWorkouts.reduce(0) { $0 + $1.duration }
    }

    private var previousMonthDuration: TimeInterval {
        previousMonthWorkouts.reduce(0) { $0 + $1.duration }
    }

    private var totalClimbsThisMonth: Int {
        currentMonthWorkouts.count
    }

    private var previousMonthClimbs: Int {
        previousMonthWorkouts.count
    }

    private var stepChangePercent: Double? {
        percentageChange(current: Double(totalStepsThisMonth), previous: Double(previousMonthStepTotal))
    }

    private var durationChangePercent: Double? {
        percentageChange(current: totalDurationThisMonth, previous: previousMonthDuration)
    }

    private var climbsChangePercent: Double? {
        percentageChange(current: Double(totalClimbsThisMonth), previous: Double(previousMonthClimbs))
    }

    private var cacheSnapshot: BestEffortCacheSnapshot {
        BestEffortCacheSnapshot(entries: bestEffortCacheEntries, workouts: workouts)
    }

    private var bestEffortBoard: BestEffortBoard {
        cacheSnapshot.board(scope: .allTime, context: .all)
    }

    private var featuredBestEffort: RankedBestEffort? {
        bestEffortBoard.primaryEffort
    }

    private var calendarDays: [CalendarDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate),
              let lastDayOfMonth = calendar.date(byAdding: DateComponents(day: -1), to: monthInterval.end) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let daysFromMonday = (firstWeekday + 5) % 7
        let gridStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: monthInterval.start) ?? monthInterval.start

        let lastWeekday = calendar.component(.weekday, from: lastDayOfMonth)
        let daysToSunday = (8 - lastWeekday) % 7
        let gridEnd = calendar.date(byAdding: .day, value: daysToSunday, to: lastDayOfMonth) ?? lastDayOfMonth

        var days: [CalendarDay] = []
        var currentDate = gridStart

        while currentDate <= gridEnd {
            let dayStart = calendar.startOfDay(for: currentDate)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let dayWorkouts = workouts.filter { workout in
                workout.date >= dayStart && workout.date < dayEnd
            }

            days.append(
                CalendarDay(
                    date: dayStart,
                    workouts: dayWorkouts,
                    isCurrentMonth: calendar.isDate(dayStart, equalTo: selectedDate, toGranularity: .month)
                )
            )

            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }

        return days
    }

    private var maxDailyStepsInMonth: Int {
        calendarDays
            .filter(\.isCurrentMonth)
            .map(\.totalSteps)
            .max() ?? 0
    }

    private var selectedMonthDayCount: Int {
        calendar.range(of: .day, in: .month, for: selectedDate)?.count ?? 0
    }

    private var cumulativeStepPoints: [ProgressTrendPoint] {
        let monthInterval = selectedMonthInterval
        let dayCount = selectedMonthDayCount
        guard dayCount > 0 else { return [] }

        let lastVisibleDay = selectedMonthContainsToday ? min(calendar.component(.day, from: Date()), dayCount) : dayCount
        let dailyTotals = Dictionary(grouping: currentMonthWorkouts) { workout in
            calendar.startOfDay(for: workout.date)
        }
        .mapValues { workouts in
            workouts.reduce(0) { $0 + $1.steps }
        }

        var cumulativeSteps = 0
        return (0..<lastVisibleDay).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: monthInterval.start) else {
                return nil
            }

            cumulativeSteps += dailyTotals[calendar.startOfDay(for: date), default: 0]
            return ProgressTrendPoint(date: date, value: cumulativeSteps)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                titleView
                streakSummaryCards
                trendHeroCard
                secondaryStatsRow
                calendarCard
                bestEffortsPreviewSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 28)
            .padding(.bottom, 128)
        }
        .scrollIndicators(.hidden)
        .background(progressBackgroundColor.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var titleView: some View {
        HStack {
            Text("Progress")
                .font(.montserratBold(size: 34))
                .foregroundStyle(primaryTextColor)

            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var streakSummaryCards: some View {
        HStack(spacing: 10) {
            ProgressSummaryCard(
                title: "WEEK STREAK",
                value: "\(weeklyStreak)",
                subtitle: "Current",
                iconName: "flame",
                accent: .accent
            )

            ProgressSummaryCard(
                title: "BEST WEEKS",
                value: "\(longestWeeklyStreak)",
                subtitle: "Longest",
                iconName: "trophy",
                accent: goldColor
            )
        }
    }

    private var trendHeroCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("TRENDS")
                    .font(.montserratSemiBold(size: 13))
                    .foregroundStyle(.accent)

                Text(totalStepsThisMonth.formatted(.number.grouping(.automatic)))
                    .font(.montserratBold(size: 40))
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                    .foregroundStyle(primaryTextColor)

                Text(selectedMonthContainsToday ? "steps this month" : "steps in \(shortMonthFormatter.string(from: selectedDate))")
                    .font(.montserratSemiBold(size: 17))
                    .foregroundStyle(secondaryTextColor)

                ChangeIndicatorView(
                    percent: stepChangePercent,
                    comparisonText: "vs \(previousComparisonLabel)"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            ProgressMonthlyLineChart(
                points: cumulativeStepPoints,
                totalDaySlots: selectedMonthDayCount
            )
            .frame(minWidth: 132, maxWidth: .infinity, minHeight: 148)
        }
        .padding(18)
        .frame(minHeight: 188)
        .background(cardBackground(accent: .accent, intensity: 0.18))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.accent.opacity(0.62), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var secondaryStatsRow: some View {
        HStack(spacing: 10) {
            ProgressMetricCard(
                title: "DURATION",
                value: compactDuration(totalDurationThisMonth),
                iconName: "clock",
                changePercent: durationChangePercent
            )

            ProgressMetricCard(
                title: "CLIMBS",
                value: "\(totalClimbsThisMonth)",
                iconName: "stairs",
                changePercent: climbsChangePercent
            )
        }
    }

    private var calendarCard: some View {
        VStack(spacing: 16) {
            calendarHeader
            calendarGrid
            calendarLegend
        }
        .padding(14)
        .background(cardBackground(accent: .white, intensity: 0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var calendarHeader: some View {
        HStack {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 36)
                    .foregroundStyle(primaryTextColor)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(monthYearFormatter.string(from: selectedDate))
                .font(.montserratBold(size: 20))
                .foregroundStyle(primaryTextColor)

            Spacer()

            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 36)
                    .foregroundStyle(canGoToNextMonth ? primaryTextColor : secondaryTextColor.opacity(0.35))
            }
            .buttonStyle(.plain)
            .disabled(!canGoToNextMonth)
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
            spacing: 8
        ) {
            ForEach(["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"], id: \.self) { day in
                Text(day)
                    .font(.montserratMedium(size: 11))
                    .foregroundStyle(secondaryTextColor)
                    .frame(height: 18)
            }

            ForEach(calendarDays) { day in
                calendarDay(day)
            }
        }
    }

    private var calendarLegend: some View {
        HStack(spacing: 12) {
            Text("FEWER STEPS")
                .font(.montserratMedium(size: 11))
                .foregroundStyle(secondaryTextColor)

            HStack(spacing: 12) {
                ForEach([0.15, 0.28, 0.41, 0.54, 0.67, 0.8, 1.0], id: \.self) { score in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(stepColor(score: score))
                        .frame(width: 14, height: 14)
                }
            }

            Text("MORE STEPS")
                .font(.montserratMedium(size: 11))
                .foregroundStyle(secondaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func calendarDay(_ day: CalendarDay) -> some View {
        Button {
            guard day.isCurrentMonth else { return }
            selectedCalendarDay = day
        } label: {
            Text("\(calendar.component(.day, from: day.date))")
                .font(.montserratMedium(size: 20))
                .foregroundStyle(dayTextColor(for: day))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(dayFill(for: day))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected(day) ? Color.accent : Color.clear, lineWidth: 2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!day.isCurrentMonth)
        .accessibilityLabel(calendarAccessibilityLabel(for: day))
    }

    private var bestEffortsPreviewSection: some View {
        Group {
            if let featuredBestEffort {
                NavigationLink {
                    BestEffortsListView(workouts: workouts)
                } label: {
                    FeaturedBestEffortCard(effort: featuredBestEffort)
                }
                .buttonStyle(.plain)
            } else {
                bestEffortsEmptyState
            }
        }
    }

    private var bestEffortsEmptyState: some View {
        NavigationLink {
            BestEffortsListView(workouts: workouts)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Best Efforts")
                    .font(.montserratBold(size: 24))
                    .foregroundStyle(primaryTextColor)

                Text("No records yet.")
                    .font(.montserratSemiBold(size: 15))
                    .foregroundStyle(goldColor)

                Text("Log a climb. Put one on the board.")
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(secondaryTextColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(cardBackground(accent: goldColor, intensity: 0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(goldColor.opacity(0.58), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var progressBackgroundColor: Color {
        .black
    }

    private var primaryTextColor: Color {
        .white
    }

    private var secondaryTextColor: Color {
        .white.opacity(0.62)
    }

    private var cardStrokeColor: Color {
        .white.opacity(0.16)
    }

    private var goldColor: Color {
        Color(red: 1.0, green: 0.78, blue: 0.18)
    }

    private func workouts(in interval: DateInterval) -> [Workout] {
        workouts.filter { workout in
            workout.date >= interval.start && workout.date < interval.end
        }
    }

    private func previousMonth() {
        selectedDate = calendar.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
        selectedCalendarDay = nil
    }

    private func nextMonth() {
        guard canGoToNextMonth else { return }
        selectedDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
        selectedCalendarDay = nil
    }

    private func percentageChange(current: Double, previous: Double) -> Double? {
        guard previous > 0 else { return nil }
        return ((current - previous) / previous) * 100
    }

    private func compactDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60

        if hours > 0 {
            return "\(hours)h \(String(format: "%02d", minutes))m"
        }

        return "\(minutes)m"
    }

    private func dayFill(for day: CalendarDay) -> LinearGradient {
        if !day.isCurrentMonth {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.09),
                    Color.white.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        guard day.totalSteps > 0, maxDailyStepsInMonth > 0 else {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.white.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        let score = min(Double(day.totalSteps) / Double(maxDailyStepsInMonth), 1)
        return LinearGradient(
            colors: [
                stepColor(score: max(score * 0.7, 0.18)).opacity(0.95),
                stepColor(score: score)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func stepColor(score: Double) -> Color {
        let clamped = min(max(score, 0), 1)
        let red = 0.17 + (0.53 * clamped)
        let green = 0.30 + (0.63 * clamped)
        let blue = 0.02 + (0.05 * clamped)
        return Color(red: red, green: green, blue: blue)
    }

    private func dayTextColor(for day: CalendarDay) -> Color {
        if !day.isCurrentMonth {
            return secondaryTextColor.opacity(0.42)
        }

        return primaryTextColor
    }

    private func isSelected(_ day: CalendarDay) -> Bool {
        if let selectedCalendarDay {
            return calendar.isDate(day.date, inSameDayAs: selectedCalendarDay.date)
        }

        return day.isCurrentMonth && calendar.isDateInToday(day.date)
    }

    private func calendarAccessibilityLabel(for day: CalendarDay) -> String {
        let dateText = day.date.formatted(.dateTime.month(.wide).day().year())
        if day.totalSteps > 0 {
            return "\(dateText), \(day.totalSteps.formatted(.number.grouping(.automatic))) steps"
        }

        return "\(dateText), no steps"
    }

    private func cardBackground(accent: Color, intensity: Double) -> LinearGradient {
        LinearGradient(
            colors: [
                accent.opacity(intensity),
                Color.white.opacity(0.035),
                Color.black.opacity(0.36)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct ProgressSummaryCard: View {
    let title: String
    let value: String
    let subtitle: String
    let iconName: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(title)
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(secondaryTextColor)

                Spacer()

                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }

            Text(value)
                .font(.montserratBold(size: 30))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(subtitle)
                .font(.montserratMedium(size: 13))
                .foregroundStyle(secondaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var cardBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.06),
                accent.opacity(0.05),
                Color.black.opacity(0.22)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var secondaryTextColor: Color {
        .white.opacity(0.7)
    }

    private var strokeColor: Color {
        .white.opacity(0.16)
    }
}

private struct ProgressMetricCard: View {
    let title: String
    let value: String
    let iconName: String
    let changePercent: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(title)
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(secondaryTextColor)

                Spacer()

                Image(systemName: iconName)
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(secondaryTextColor.opacity(0.32))
            }

            Text(value)
                .font(.montserratBold(size: 30))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            ChangeIndicatorView(
                percent: changePercent,
                comparisonText: ""
            )
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .padding(16)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var cardBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.055),
                Color.white.opacity(0.025),
                Color.black.opacity(0.28)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var primaryTextColor: Color {
        .white
    }

    private var secondaryTextColor: Color {
        .white.opacity(0.66)
    }

    private var strokeColor: Color {
        .white.opacity(0.15)
    }
}

private struct ChangeIndicatorView: View {
    let percent: Double?
    let comparisonText: String

    var body: some View {
        HStack(spacing: 6) {
            if let percent {
                let isPositive = percent >= 0

                Image(systemName: isPositive ? "arrow.up" : "arrow.down")
                    .font(.system(size: 13, weight: .bold))

                Text("\(Int(abs(percent).rounded()))%")
                    .font(.montserratSemiBold(size: 13))

                if !comparisonText.isEmpty {
                    Text(comparisonText)
                        .font(.montserratMedium(size: 13))
                        .foregroundStyle(secondaryTextColor)
                }
            } else {
                Text(comparisonText.isEmpty ? "No prior data" : "No prior data \(comparisonText)")
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(secondaryTextColor)
            }
        }
        .foregroundStyle(changeColor)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private var changeColor: Color {
        guard let percent else {
            return secondaryTextColor
        }

        return percent >= 0 ? .accent : .red
    }

    private var secondaryTextColor: Color {
        .white.opacity(0.62)
    }
}

private struct ProgressMonthlyLineChart: View {
    let points: [ProgressTrendPoint]
    let totalDaySlots: Int

    var body: some View {
        GeometryReader { geometry in
            let chartPoints = resolvedPoints(in: geometry.size)

            ZStack {
                if chartPoints.count > 1 {
                    chartFill(points: chartPoints, size: geometry.size)
                        .fill(.accent.opacity(0.16))

                    chartPath(points: chartPoints)
                        .stroke(.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .shadow(color: .accent.opacity(0.45), radius: 8, x: 0, y: 0)

                    if let lastPoint = chartPoints.last {
                        Circle()
                            .fill(.accent)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                            .position(lastPoint)
                    }
                }
            }
        }
    }

    private func resolvedPoints(in size: CGSize) -> [CGPoint] {
        guard points.count > 1 else { return [] }

        let maxValue = max(points.map(\.value).max() ?? 1, 1)
        let daySpan = max(totalDaySlots - 1, 1)

        return points.enumerated().map { index, point in
            let x = CGFloat(index) / CGFloat(daySpan) * size.width
            let yRatio = CGFloat(point.value) / CGFloat(maxValue)
            let y = size.height - (yRatio * size.height)
            return CGPoint(x: x, y: y)
        }
    }

    private func chartPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let firstPoint = points.first else { return path }

        path.move(to: firstPoint)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }

        return path
    }

    private func chartFill(points: [CGPoint], size: CGSize) -> Path {
        var path = chartPath(points: points)
        guard let firstPoint = points.first, let lastPoint = points.last else { return path }

        path.addLine(to: CGPoint(x: lastPoint.x, y: size.height))
        path.addLine(to: CGPoint(x: firstPoint.x, y: size.height))
        path.closeSubpath()
        return path
    }
}

private struct FeaturedBestEffortCard: View {
    let effort: RankedBestEffort

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image("best-effort-laurel-wreath")
                .resizable()
                .scaledToFit()
                .frame(width: 122, height: 112)
                .opacity(0.78)
                .padding(.trailing, 22)
                .padding(.bottom, 32)

            Text("View all")
                .font(.montserratSemiBold(size: 12))
                .foregroundStyle(effort.trophyColor.opacity(0.72))
                .padding(.trailing, 18)
                .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 8) {
                Text("Best Efforts")
                    .font(.montserratBold(size: 22))
                    .foregroundStyle(primaryTextColor)

                Text(effort.metric.title)
                    .font(.montserratSemiBold(size: 15))
                    .foregroundStyle(effort.trophyColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(valueText)
                    .font(.montserratBold(size: 42))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(effort.dateText)
                    .font(.montserratMedium(size: 15))
                    .foregroundStyle(secondaryTextColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
        .frame(maxWidth: .infinity, minHeight: 162)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(effort.trophyColor.opacity(0.62), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel("Best Efforts, \(effort.metric.title), \(valueText), \(effort.dateText)")
    }

    private var valueText: String {
        switch effort.metric {
        case .mostSteps, .mostStepsInTime, .highestAverageSPM:
            return effort.compactValueText
        case .longestClimb, .fastestStepTarget:
            return effort.compactValueText
        }
    }

    private var cardBackground: LinearGradient {
        LinearGradient(
            colors: [
                effort.trophyColor.opacity(0.2),
                Color.white.opacity(0.04),
                Color.black.opacity(0.42)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var primaryTextColor: Color {
        .white
    }

    private var secondaryTextColor: Color {
        .white.opacity(0.62)
    }
}

private struct ProgressTrendPoint: Identifiable {
    let date: Date
    let value: Int

    var id: Date {
        date
    }
}

private struct CalendarDay: Identifiable {
    let date: Date
    let workouts: [Workout]
    let isCurrentMonth: Bool

    var id: Date {
        date
    }

    var hasWorkout: Bool {
        !workouts.isEmpty
    }

    var totalSteps: Int {
        workouts.reduce(0) { $0 + $1.steps }
    }
}

#Preview("Progress Sheet - Dark") {
    let calendar = Calendar.current
    let sampleWorkouts = (0..<18).map { index in
        Workout(
            date: calendar.date(byAdding: .day, value: -index, to: Date()) ?? Date(),
            duration: TimeInterval(1_800 + (index * 120)),
            steps: 1_200 + (index * 220),
            floors: (1_200 + (index * 220)) / 16
        )
    }

    NavigationStack {
        ProgressSheet(workouts: sampleWorkouts)
    }
    .preferredColorScheme(.dark)
    .modelContainer(
        for: [
            Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self
        ],
        inMemory: true
    )
}
