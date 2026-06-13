//
//  WorkoutTrendsView.swift
//  AscendApp
//
//  Created by ChatGPT on 5/25/24.
//

import SwiftUI

struct WorkoutTrendsView: View {
    let workouts: [Workout]
    let initialMonth: Date

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var selectedRange: WorkoutTrendDetailRange = .month

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var calendar: Calendar { Calendar.current }

    private var monthInterval: DateInterval? {
        calendar.dateInterval(of: .month, for: initialMonth)
    }

    private var monthlyWorkouts: [Workout] {
        guard let monthInterval else { return [] }
        return workouts
            .filter { monthInterval.contains($0.date) }
            .sorted { $0.date < $1.date }
    }

    private var visibleInterval: DateInterval? {
        switch selectedRange {
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: initialMonth)
        case .month:
            return monthInterval
        case .threeMonths:
            guard let end = monthInterval?.end,
                  let start = calendar.date(byAdding: .month, value: -2, to: calendar.dateInterval(of: .month, for: initialMonth)?.start ?? initialMonth)
            else { return nil }
            return DateInterval(start: start, end: end)
        case .year:
            return calendar.dateInterval(of: .year, for: initialMonth)
        case .all:
            guard let first = workouts.map(\.date).min(),
                  let last = workouts.map(\.date).max() else {
                return nil
            }
            let start = calendar.startOfDay(for: first)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) ?? last
            return DateInterval(start: start, end: end)
        }
    }

    private var comparisonCurrentInterval: DateInterval? {
        guard let visibleInterval else { return nil }
        let now = Date()

        guard visibleInterval.contains(now) else {
            return visibleInterval
        }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return DateInterval(start: visibleInterval.start, end: min(tomorrow, visibleInterval.end))
    }

    private var comparisonUsesElapsedWindow: Bool {
        guard selectedRange != .all,
              let visibleInterval else {
            return false
        }

        return visibleInterval.contains(Date())
    }

    private var comparisonPreviousInterval: DateInterval? {
        guard let visibleInterval,
              let comparisonCurrentInterval,
              let previousStart = calendar.date(
                byAdding: selectedRange.previousComponent,
                value: -selectedRange.previousValue,
                to: visibleInterval.start
              ),
              let previousFullEnd = calendar.date(
                byAdding: selectedRange.previousComponent,
                value: -selectedRange.previousValue,
                to: visibleInterval.end
              )
        else { return nil }

        guard comparisonUsesElapsedWindow else {
            return DateInterval(start: previousStart, end: previousFullEnd)
        }

        let elapsedDays = calendar.dateComponents(
            [.day],
            from: comparisonCurrentInterval.start,
            to: comparisonCurrentInterval.end
        ).day ?? 0
        let previousElapsedEnd = calendar.date(byAdding: .day, value: elapsedDays, to: previousStart) ?? previousFullEnd
        return DateInterval(start: previousStart, end: min(previousElapsedEnd, previousFullEnd))
    }

    private var visibleWorkouts: [Workout] {
        guard let visibleInterval else { return [] }
        return workouts
            .filter { visibleInterval.contains($0.date) }
            .sorted { $0.date < $1.date }
    }

    private var previousPeriodWorkouts: [Workout] {
        guard let comparisonPreviousInterval else { return [] }
        return workouts.filter { comparisonPreviousInterval.contains($0.date) }
    }

    private var visibleStepTotal: Int {
        visibleWorkouts.reduce(0) { $0 + $1.steps }
    }

    private var currentComparisonStepTotal: Int {
        guard let comparisonCurrentInterval else { return visibleStepTotal }
        return workouts
            .filter { comparisonCurrentInterval.contains($0.date) }
            .reduce(0) { $0 + $1.steps }
    }

    private var previousStepTotal: Int {
        previousPeriodWorkouts.reduce(0) { $0 + $1.steps }
    }

    private var visibleDayCount: Int {
        guard let interval = comparisonCurrentInterval ?? visibleInterval else { return 1 }
        let start = calendar.startOfDay(for: interval.start)
        let end = calendar.startOfDay(for: interval.end)
        return max(calendar.dateComponents([.day], from: start, to: end).day ?? 1, 1)
    }

    private var dailyAverage: Int {
        visibleStepTotal / max(visibleDayCount, 1)
    }

    private var stepChange: Double? {
        guard previousStepTotal > 0 else { return nil }
        return Double(currentComparisonStepTotal - previousStepTotal) / Double(previousStepTotal) * 100
    }

    private var comparisonLabel: String {
        guard comparisonUsesElapsedWindow,
              let comparisonPreviousInterval else {
            return selectedRange.previousLabel(from: initialMonth, calendar: calendar)
        }

        return selectedRange.elapsedPreviousLabel(for: comparisonPreviousInterval, calendar: calendar)
    }

    private var trendChartPoints: [ProgressLineChartPoint] {
        switch selectedRange.bucketStyle {
        case .day:
            return dailyStepPoints()
        case .month:
            return monthlyStepPoints()
        }
    }

    private var bestEffortBoard: BestEffortBoard {
        BestEffortRankingBuilder.board(
            from: monthlyWorkouts,
            scope: .allTime,
            context: .all
        )
    }

    private var topAchievement: RankedBestEffort? {
        bestEffortBoard.primaryEffort
    }

    private var totalDuration: TimeInterval {
        monthlyWorkouts.reduce(0) { $0 + $1.duration }
    }

    private var highestOutput: (steps: Int, date: Date)? {
        dailyTotals(in: monthlyWorkouts)
            .max { lhs, rhs in lhs.value < rhs.value }
            .map { (steps: $0.value, date: $0.key) }
    }

    private var fastestClimb: Workout? {
        monthlyWorkouts
            .filter { $0.stepsPerMinute != nil }
            .max { ($0.stepsPerMinute ?? 0) < ($1.stepsPerMinute ?? 0) }
    }

    private var longestSession: Workout? {
        monthlyWorkouts.max { $0.duration < $1.duration }
    }

    private var averageHeartRate: Int? {
        let values = monthlyWorkouts.compactMap(\.avgHeartRate)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    private var highlightMetrics: [TrendMetric] {
        var metrics: [TrendMetric] = []
        let dailyTotals = sortedDailyTotals(in: monthlyWorkouts)

        if let highestOutput {
            let points = dailyStepMetricPoints(from: dailyTotals, prefix: "highest-output")
            metrics.append(
                TrendMetric(
                    id: "highest-output",
                    title: "Highest Output",
                    subtitle: "Most steps in a day",
                    value: "\(formattedInteger(highestOutput.steps)) steps",
                    detail: shortDate(highestOutput.date),
                    points: points,
                    sparkValues: points.map(\.value),
                    color: .accentColor,
                    xAxisStyle: .monthDay,
                    yAxisLabel: compactAxisLabel
                )
            )
        }

        if let fastestClimb, let pace = fastestClimb.stepsPerMinute {
            let points = paceMetricPoints(from: monthlyWorkouts, prefix: "fastest-climb")
            metrics.append(
                TrendMetric(
                    id: "fastest-climb",
                    title: "Fastest Climb",
                    subtitle: "Highest avg SPM",
                    value: "\(Int(pace.rounded())) SPM",
                    detail: shortDate(fastestClimb.date),
                    points: points,
                    sparkValues: points.map(\.value),
                    color: .accentColor,
                    xAxisStyle: .monthDay,
                    yAxisLabel: { "\(Int($0.rounded()))" }
                )
            )
        }

        if let longestSession {
            let points = durationMetricPoints(from: monthlyWorkouts, prefix: "longest-session")
            metrics.append(
                TrendMetric(
                    id: "longest-session",
                    title: "Longest Session",
                    subtitle: "Most time climbing",
                    value: clockDuration(longestSession.duration),
                    detail: shortDate(longestSession.date),
                    points: points,
                    sparkValues: points.map(\.value),
                    color: .accentColor,
                    xAxisStyle: .monthDay,
                    yAxisLabel: clockDuration
                )
            )
        }

        return metrics
    }

    private var breakdownMetrics: [TrendMetric] {
        let heartRatePoints = heartRateMetricPoints(from: monthlyWorkouts, prefix: "heart-rate")
        let pacePoints = paceMetricPoints(from: monthlyWorkouts, prefix: "spm")
        let durationPoints = durationMetricPoints(from: monthlyWorkouts, prefix: "duration")

        return [
            TrendMetric(
                id: "heart-rate",
                title: "Heart Rate",
                subtitle: averageHeartRate.map { "Avg \($0) BPM" } ?? "No heart-rate data",
                value: averageHeartRate.map { "\($0) BPM" } ?? "--",
                detail: "monthly avg",
                points: heartRatePoints,
                sparkValues: heartRatePoints.map(\.value),
                color: .red,
                xAxisStyle: .monthDay,
                yAxisLabel: { "\(Int($0.rounded()))" }
            ),
            TrendMetric(
                id: "spm-cadence",
                title: "SPM",
                subtitle: "Cadence and pacing",
                value: averageSPMText,
                detail: "avg pace",
                points: pacePoints,
                sparkValues: pacePoints.map(\.value),
                color: .accentColor,
                xAxisStyle: .monthDay,
                yAxisLabel: { "\(Int($0.rounded()))" }
            ),
            TrendMetric(
                id: "duration",
                title: "Duration",
                subtitle: "Time spent climbing",
                value: clockDuration(totalDuration),
                detail: "total",
                points: durationPoints,
                sparkValues: durationPoints.map(\.value),
                color: .blue,
                xAxisStyle: .monthDay,
                yAxisLabel: clockDuration
            )
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                heroCard
                recapCard
                highlightsSection
                breakdownSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .themedBackground()
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(foregroundPrimary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(cardFill))
                    .overlay(Circle().stroke(cardStroke, lineWidth: 1))
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("TRENDS")
                        .font(.montserratBold(size: 12))
                        .kerning(2)
                        .foregroundStyle(.accent)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(formattedInteger(visibleStepTotal))
                            .font(.montserratBold(size: 44))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Text(selectedRange.summaryLabel)
                            .font(.montserratSemiBold(size: 18))
                            .foregroundStyle(.white.opacity(0.82))
                    }

                    comparisonLine
                }

                Spacer(minLength: 14)

                dailyAverageChip
                    .padding(.top, 38)
            }

            if trendChartPoints.isEmpty {
                noDataInPeriodState
                    .padding(.top, 12)
            } else {
                ProgressLineChartView(
                    title: "Steps",
                    points: trendChartPoints,
                    colorScheme: .dark,
                    height: 222,
                    xAxisStyle: selectedRange.bucketStyle == .day ? .monthDay : .monthYear,
                    emptyText: "No steps to chart.",
                    yAxisLabel: compactAxisLabel
                )
            }

            rangePicker
        }
        .padding(22)
        .background(heroBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    private var comparisonLine: some View {
        HStack(spacing: 6) {
            if let stepChange, abs(stepChange) >= 1 {
                Image(systemName: stepChange >= 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(comparisonColor(for: stepChange))

                Text(formattedPercent(abs(stepChange)))
                    .font(.montserratBold(size: 14))
                    .foregroundStyle(comparisonColor(for: stepChange))

                Text("vs \(comparisonLabel)")
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(.white.opacity(0.62))
            } else if previousPeriodWorkouts.isEmpty {
                Text("New \(selectedRange.baselineLabel)")
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(.white.opacity(0.62))
            } else {
                Text("Even vs \(comparisonLabel)")
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
    }

    private var dailyAverageChip: some View {
        HStack(spacing: 10) {
            TinyBarIcon()
                .foregroundStyle(.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Daily avg")
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(.white.opacity(0.58))
                Text("\(formattedInteger(dailyAverage)) steps")
                    .font(.montserratSemiBold(size: 13))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var rangePicker: some View {
        HStack(spacing: 0) {
            ForEach(WorkoutTrendDetailRange.allCases) { range in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        selectedRange = range
                    }
                } label: {
                    Text(range.title)
                        .font(.montserratSemiBold(size: 13))
                        .foregroundStyle(selectedRange == range ? Color.ascendAccent : .white.opacity(0.62))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            Capsule()
                                .fill(selectedRange == range ? Color.ascendAccent.opacity(0.12) : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(.black.opacity(0.2))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 1))
    }

    private var recapCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("\(monthName) Recap")
                .font(.montserratBold(size: 18))
                .foregroundStyle(foregroundPrimary)

            HStack(spacing: 0) {
                recapStat(value: formattedInteger(monthlyStepTotal), label: "steps")
                recapDivider
                recapStat(value: "\(monthlyWorkouts.count)", label: "workouts")
                recapDivider
                recapStat(value: clockDuration(totalDuration), label: "total time")
            }

            achievementSummary
        }
        .padding(18)
        .background(cardBackground(cornerRadius: 22))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    private func recapStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(.montserratBold(size: 17))
                .foregroundStyle(foregroundPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.66)

            Text(label)
                .font(.montserratMedium(size: 11))
                .foregroundStyle(foregroundSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recapDivider: some View {
        Rectangle()
            .fill(cardStroke)
            .frame(width: 1, height: 46)
            .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var achievementSummary: some View {
        if let topAchievement {
            HStack(spacing: 10) {
                Image("best-effort-laurel-wreath")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .opacity(0.82)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Top Achievement")
                        .font(.montserratSemiBold(size: 12))
                        .foregroundStyle(.accent)
                    Text(topAchievement.metric.title)
                        .font(.montserratSemiBold(size: 13))
                        .foregroundStyle(foregroundPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text("\(topAchievement.dateText) • \(topAchievement.valueText)")
                        .font(.montserratMedium(size: 11))
                        .foregroundStyle(foregroundSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.black.opacity(effectiveColorScheme == .dark ? 0.2 : 0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Top Achievement")
                    .font(.montserratSemiBold(size: 12))
                    .foregroundStyle(.accent)
                Text("No record yet")
                    .font(.montserratSemiBold(size: 13))
                    .foregroundStyle(foregroundPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.black.opacity(effectiveColorScheme == .dark ? 0.2 : 0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Highlights")

            VStack(spacing: 0) {
                ForEach(highlightMetrics) { metric in
                    if metric.id != highlightMetrics.first?.id {
                        trendDivider
                    }
                    trendRow(metric)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(cardBackground(cornerRadius: 20))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(cardStroke, lineWidth: 1)
            )
        }
    }

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Breakdown")

            VStack(spacing: 0) {
                ForEach(breakdownMetrics) { metric in
                    if metric.id != breakdownMetrics.first?.id {
                        trendDivider
                    }
                    trendRow(metric)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(cardBackground(cornerRadius: 20))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(cardStroke, lineWidth: 1)
            )
        }
    }

    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(.montserratBold(size: 18))
            .foregroundStyle(foregroundPrimary)
        .padding(.horizontal, 4)
    }

    private func trendRow(_ metric: TrendMetric) -> some View {
        NavigationLink {
            TrendMetricDetailView(metric: metric, colorScheme: effectiveColorScheme)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(metric.title)
                        .font(.montserratSemiBold(size: 15))
                        .foregroundStyle(foregroundPrimary)
                        .lineLimit(2)
                    Text(metric.subtitle)
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(foregroundSecondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 5) {
                    Text(metric.value)
                        .font(.montserratSemiBold(size: 14))
                        .foregroundStyle(foregroundPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(metric.detail)
                        .font(.montserratMedium(size: 11))
                        .foregroundStyle(foregroundSecondary)
                        .lineLimit(1)
                }
                .frame(width: 92, alignment: .leading)

                TrendMiniSparkline(values: metric.sparkValues, color: metric.color)
                    .frame(width: 72, height: 36)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }

    private var trendDivider: some View {
        Divider()
            .background(cardStroke)
            .padding(.leading, 0)
    }

    private var noDataInPeriodState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.36))

            Text("No workouts logged for this period.")
                .font(.montserratSemiBold(size: 14))
                .foregroundStyle(.white.opacity(0.82))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 170)
    }

    private var heroBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(red: 0.035, green: 0.038, blue: 0.034))
            .overlay(alignment: .bottomTrailing) {
                LinearGradient(
                    colors: [
                        Color.ascendAccent.opacity(0.18),
                        .clear
                    ],
                    startPoint: .bottomTrailing,
                    endPoint: .topLeading
                )
            }
    }

    private func cardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(cardFill)
            .overlay(alignment: .topLeading) {
                LinearGradient(
                    colors: [
                        .white.opacity(effectiveColorScheme == .dark ? 0.055 : 0.12),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .center
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay(alignment: .bottomTrailing) {
                RadialGradient(
                    colors: [
                        Color.ascendAccent.opacity(effectiveColorScheme == .dark ? 0.075 : 0.045),
                        .clear
                    ],
                    center: .bottomTrailing,
                    startRadius: 10,
                    endRadius: 260
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
    }

    private func dailyStepPoints() -> [ProgressLineChartPoint] {
        guard let visibleInterval else { return [] }
        let totals = dailyTotals(in: visibleWorkouts)
        let days = days(in: visibleInterval)
        return days.map { day in
            let value = Double(totals[day, default: 0])
            return ProgressLineChartPoint(
                id: "day-\(day.timeIntervalSince1970)",
                date: day,
                value: value,
                valueText: "\(formattedInteger(Int(value.rounded()))) steps",
                dateText: day.formatted(.dateTime.month(.abbreviated).day())
            )
        }
    }

    private func monthlyStepPoints() -> [ProgressLineChartPoint] {
        guard let visibleInterval else { return [] }
        let bucketed = Dictionary(grouping: visibleWorkouts) { workout in
            calendar.dateInterval(of: .month, for: workout.date)?.start ?? calendar.startOfDay(for: workout.date)
        }

        return months(in: visibleInterval).map { month in
            let value = Double(bucketed[month, default: []].reduce(0) { $0 + $1.steps })
            return ProgressLineChartPoint(
                id: "month-\(month.timeIntervalSince1970)",
                date: month,
                value: value,
                valueText: "\(formattedInteger(Int(value.rounded()))) steps",
                dateText: month.formatted(.dateTime.month(.abbreviated).year())
            )
        }
    }

    private func sortedDailyTotals(in workouts: [Workout]) -> [(key: Date, value: Int)] {
        dailyTotals(in: workouts).sorted { $0.key < $1.key }
    }

    private func dailyStepMetricPoints(
        from dailyTotals: [(key: Date, value: Int)],
        prefix: String
    ) -> [ProgressLineChartPoint] {
        dailyTotals.map { day, steps in
            ProgressLineChartPoint(
                id: "\(prefix)-\(day.timeIntervalSince1970)",
                date: day,
                value: Double(steps),
                valueText: "\(formattedInteger(steps)) steps",
                dateText: shortDate(day)
            )
        }
    }

    private func paceMetricPoints(
        from workouts: [Workout],
        prefix: String
    ) -> [ProgressLineChartPoint] {
        workouts.compactMap { workout in
            guard let pace = workout.stepsPerMinute else {
                return nil
            }
            return ProgressLineChartPoint(
                id: "\(prefix)-\(workout.id.uuidString)",
                date: workout.date,
                value: pace,
                valueText: "\(Int(pace.rounded())) SPM",
                dateText: shortDate(workout.date)
            )
        }
    }

    private func durationMetricPoints(
        from workouts: [Workout],
        prefix: String
    ) -> [ProgressLineChartPoint] {
        workouts
            .filter { $0.duration > 0 }
            .map { workout in
                ProgressLineChartPoint(
                    id: "\(prefix)-\(workout.id.uuidString)",
                    date: workout.date,
                    value: workout.duration,
                    valueText: clockDuration(workout.duration),
                    dateText: shortDate(workout.date)
                )
            }
    }

    private func heartRateMetricPoints(
        from workouts: [Workout],
        prefix: String
    ) -> [ProgressLineChartPoint] {
        workouts.compactMap { workout in
            guard let heartRate = workout.avgHeartRate else {
                return nil
            }
            return ProgressLineChartPoint(
                id: "\(prefix)-\(workout.id.uuidString)",
                date: workout.date,
                value: Double(heartRate),
                valueText: "\(heartRate) BPM",
                dateText: shortDate(workout.date)
            )
        }
    }

    private func dailyTotals(in workouts: [Workout]) -> [Date: Int] {
        workouts.reduce(into: [:]) { totals, workout in
            let day = calendar.startOfDay(for: workout.date)
            totals[day, default: 0] += workout.steps
        }
    }

    private func days(in interval: DateInterval) -> [Date] {
        var result: [Date] = []
        var current = calendar.startOfDay(for: interval.start)
        let end = calendar.startOfDay(for: interval.end)
        while current < end {
            result.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? end
        }
        return result
    }

    private func months(in interval: DateInterval) -> [Date] {
        var result: [Date] = []
        var current = calendar.dateInterval(of: .month, for: interval.start)?.start ?? interval.start
        let end = calendar.dateInterval(of: .month, for: interval.end)?.start ?? interval.end
        while current <= end {
            result.append(current)
            guard let next = calendar.date(byAdding: .month, value: 1, to: current) else { break }
            current = next
        }
        return result
    }

    private var monthlyStepTotal: Int {
        monthlyWorkouts.reduce(0) { $0 + $1.steps }
    }

    private var monthName: String {
        initialMonth.formatted(.dateTime.month(.wide))
    }

    private var averageSPMText: String {
        let totalMinutes = totalDuration / 60
        guard totalMinutes > 0 else { return "--" }
        return "\(Int((Double(monthlyStepTotal) / totalMinutes).rounded())) SPM"
    }

    private func compactAxisLabel(_ value: Double) -> String {
        if value >= 1_000 {
            return "\(Int((value / 1_000).rounded()))K"
        }
        return "\(Int(value.rounded()))"
    }

    private func comparisonColor(for change: Double) -> Color {
        change >= 0 ? .accentColor : .red
    }

    private func formattedInteger(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    private func formattedPercent(_ value: Double) -> String {
        if value >= 1_000 {
            return "999+%"
        }
        return "\(value.formatted(.number.precision(.fractionLength(0))))%"
    }

    private func clockDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        let minuteText = String(format: "%02d", minutes)
        let secondText = String(format: "%02d", seconds)

        if hours > 0 {
            return "\(hours):\(minuteText):\(secondText)"
        }

        return "\(minutes):\(secondText)"
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    private var foregroundPrimary: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var foregroundSecondary: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.58)
    }

    private var foregroundSubtle: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.36) : .black.opacity(0.38)
    }

    private var cardFill: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.055) : .black.opacity(0.035)
    }

    private var cardStroke: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.09) : .black.opacity(0.08)
    }
}

private enum WorkoutTrendDetailRange: String, CaseIterable, Identifiable {
    case week
    case month
    case threeMonths
    case year
    case all

    enum BucketStyle {
        case day
        case month
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .threeMonths: return "3M"
        case .year: return "Year"
        case .all: return "All"
        }
    }

    var summaryLabel: String {
        switch self {
        case .week: return "steps this week"
        case .month: return "steps this month"
        case .threeMonths: return "steps in 3 months"
        case .year: return "steps this year"
        case .all: return "steps all time"
        }
    }

    var baselineLabel: String {
        switch self {
        case .week: return "weekly baseline"
        case .month: return "monthly baseline"
        case .threeMonths: return "3-month baseline"
        case .year: return "yearly baseline"
        case .all: return "all-time baseline"
        }
    }

    var bucketStyle: BucketStyle {
        switch self {
        case .week, .month:
            return .day
        case .threeMonths, .year, .all:
            return .month
        }
    }

    var previousComponent: Calendar.Component {
        switch self {
        case .week: return .weekOfYear
        case .month: return .month
        case .threeMonths: return .month
        case .year, .all: return .year
        }
    }

    var previousValue: Int {
        switch self {
        case .week, .month, .year, .all:
            return 1
        case .threeMonths:
            return 3
        }
    }

    func previousLabel(from date: Date, calendar: Calendar) -> String {
        switch self {
        case .week:
            return "last week"
        case .month:
            let previous = calendar.date(byAdding: .month, value: -1, to: date) ?? date
            return previous.formatted(.dateTime.month(.wide))
        case .threeMonths:
            return "previous 3M"
        case .year:
            let previous = calendar.date(byAdding: .year, value: -1, to: date) ?? date
            return previous.formatted(.dateTime.year())
        case .all:
            return "prior year"
        }
    }

    func elapsedPreviousLabel(for interval: DateInterval, calendar: Calendar) -> String {
        switch self {
        case .week, .month:
            guard let inclusiveEnd = calendar.date(byAdding: .day, value: -1, to: interval.end) else {
                return interval.start.formatted(.dateTime.month(.abbreviated).day())
            }
            return "\(interval.start.formatted(.dateTime.month(.abbreviated).day()))-\(calendar.component(.day, from: inclusiveEnd))"
        case .threeMonths:
            return "previous 3M to date"
        case .year:
            return "\(interval.start.formatted(.dateTime.year())) to date"
        case .all:
            return "prior period to date"
        }
    }
}

private struct TrendMetric: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let value: String
    let detail: String
    let points: [ProgressLineChartPoint]
    let sparkValues: [Double]
    let color: Color
    let xAxisStyle: ProgressLineChartXAxisStyle
    let yAxisLabel: (Double) -> String
}

private struct TrendMetricDetailView: View {
    let metric: TrendMetric
    let colorScheme: ColorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                metricHeader
                chartCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .themedBackground()
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var metricHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(metric.title.uppercased())
                .font(.montserratBold(size: 12))
                .kerning(2)
                .foregroundStyle(metric.color)

            Text(metric.value)
                .font(.montserratBold(size: 44))
                .foregroundStyle(foregroundPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            VStack(alignment: .leading, spacing: 4) {
                Text(metric.subtitle)
                    .font(.montserratSemiBold(size: 17))
                    .foregroundStyle(foregroundSecondary)
                Text(metric.detail)
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(foregroundSubtle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(cardBackground(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Chart")
                .font(.montserratBold(size: 18))
                .foregroundStyle(foregroundPrimary)

            ProgressLineChartView(
                title: metric.title,
                points: metric.points,
                colorScheme: colorScheme,
                accentColor: metric.color,
                height: 320,
                xAxisStyle: metric.xAxisStyle,
                emptyText: "No data to chart.",
                yAxisLabel: metric.yAxisLabel
            )
        }
        .padding(18)
        .background(cardBackground(cornerRadius: 22))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    private func cardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(cardFill)
            .overlay(alignment: .topLeading) {
                LinearGradient(
                    colors: [
                        .white.opacity(colorScheme == .dark ? 0.055 : 0.12),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .center
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay(alignment: .bottomTrailing) {
                RadialGradient(
                    colors: [
                        metric.color.opacity(colorScheme == .dark ? 0.08 : 0.05),
                        .clear
                    ],
                    center: .bottomTrailing,
                    startRadius: 8,
                    endRadius: 260
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
    }

    private var foregroundPrimary: Color {
        colorScheme == .dark ? .white : .black
    }

    private var foregroundSecondary: Color {
        colorScheme == .dark ? .white.opacity(0.64) : .black.opacity(0.6)
    }

    private var foregroundSubtle: Color {
        colorScheme == .dark ? .white.opacity(0.42) : .black.opacity(0.42)
    }

    private var cardFill: Color {
        colorScheme == .dark ? .white.opacity(0.055) : .black.opacity(0.035)
    }

    private var cardStroke: Color {
        colorScheme == .dark ? .white.opacity(0.09) : .black.opacity(0.08)
    }
}

private struct TinyBarIcon: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            Capsule().frame(width: 4, height: 14)
            Capsule().frame(width: 4, height: 24)
            Capsule().frame(width: 4, height: 10)
        }
    }
}

private struct TrendMiniSparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let points = chartPoints(in: proxy.size)
            ZStack {
                if points.count >= 2 {
                    fillPath(points: points, size: proxy.size)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.28), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    linePath(points: points)
                        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func chartPoints(in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let maxValue = max(values.max() ?? 0, 1)
        let minValue = min(values.min() ?? 0, 0)
        let valueRange = max(maxValue - minValue, 1)
        let xStep = values.count > 1 ? size.width / CGFloat(values.count - 1) : 0

        return values.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) * xStep,
                y: (1 - CGFloat((value - minValue) / valueRange)) * size.height
            )
        }
    }

    private func linePath(points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
        }
    }

    private func fillPath(points: [CGPoint], size: CGSize) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: first.x, y: size.height))
            path.addLine(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.closeSubpath()
        }
    }
}
