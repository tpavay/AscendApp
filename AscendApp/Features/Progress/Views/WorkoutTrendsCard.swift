//
//  WorkoutTrendsCard.swift
//  AscendApp
//
//  Created by ChatGPT on 5/25/24.
//

import SwiftUI

struct WorkoutTrendsCard: View {
    let workouts: [Workout]
    let selectedDate: Date
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    private var calendar: Calendar { Calendar.current }
    
    private var monthlyWorkouts: [Workout] {
        workouts.filter { calendar.isDate($0.date, equalTo: selectedDate, toGranularity: .month) }
    }

    private var monthInterval: DateInterval? {
        calendar.dateInterval(of: .month, for: selectedDate)
    }

    private var isSelectedMonthCurrent: Bool {
        calendar.isDate(selectedDate, equalTo: Date(), toGranularity: .month)
    }

    private var sortedMonthlyWorkouts: [Workout] {
        monthlyWorkouts.sorted { $0.date < $1.date }
    }

    private var comparisonCurrentInterval: DateInterval? {
        guard let monthInterval else { return nil }
        guard isSelectedMonthCurrent else {
            return monthInterval
        }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        return DateInterval(start: monthInterval.start, end: min(tomorrow, monthInterval.end))
    }

    private var comparisonPreviousInterval: DateInterval? {
        guard let comparisonCurrentInterval,
              let previousMonth = calendar.date(byAdding: .month, value: -1, to: selectedDate),
              let previousMonthInterval = calendar.dateInterval(of: .month, for: previousMonth)
        else { return nil }

        guard isSelectedMonthCurrent else {
            return previousMonthInterval
        }

        let elapsedDays = calendar.dateComponents(
            [.day],
            from: comparisonCurrentInterval.start,
            to: comparisonCurrentInterval.end
        ).day ?? 0
        let previousEnd = calendar.date(
            byAdding: .day,
            value: elapsedDays,
            to: previousMonthInterval.start
        ) ?? previousMonthInterval.end

        return DateInterval(start: previousMonthInterval.start, end: min(previousEnd, previousMonthInterval.end))
    }

    private var previousComparisonWorkouts: [Workout] {
        guard let comparisonPreviousInterval else { return [] }
        return workouts.filter { comparisonPreviousInterval.contains($0.date) }
    }

    private var monthlyTotalMetric: Int {
        monthlyWorkouts.reduce(0) { $0 + $1.steps }
    }

    private var currentComparisonTotalMetric: Int {
        guard let comparisonCurrentInterval else { return monthlyTotalMetric }
        return workouts
            .filter { comparisonCurrentInterval.contains($0.date) }
            .reduce(0) { $0 + $1.steps }
    }

    private var previousComparisonTotalMetric: Int {
        previousComparisonWorkouts.reduce(0) { $0 + $1.steps }
    }

    private var volumeChange: Double? {
        guard previousComparisonTotalMetric > 0 else { return nil }
        return Double(currentComparisonTotalMetric - previousComparisonTotalMetric) / Double(previousComparisonTotalMetric) * 100
    }

    private var sparklinePoints: [WorkoutTrendPreviewPoint] {
        guard !sortedMonthlyWorkouts.isEmpty else { return [] }
        var cumulativeTotal = 0.0
        let denominator = max(sortedMonthlyWorkouts.count, 1)

        var points = [WorkoutTrendPreviewPoint(x: 0, y: 0)]
        for (index, workout) in sortedMonthlyWorkouts.enumerated() {
            cumulativeTotal += Double(workout.steps)
            let xPosition = Double(index + 1) / Double(denominator)
            points.append(WorkoutTrendPreviewPoint(x: xPosition, y: cumulativeTotal))
        }

        return points
    }
    
    var body: some View {
        NavigationLink {
            WorkoutTrendsView(
                workouts: workouts,
                initialMonth: selectedDate
            )
        } label: {
            ZStack(alignment: .bottom) {
                cardBackground

                if !monthlyWorkouts.isEmpty {
                    WorkoutTrendPreviewSparkline(
                        points: sparklinePoints,
                        color: accentColor
                    )
                    .frame(height: 194)
                    .padding(.bottom, 0)
                }

                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, 26)

                    if monthlyWorkouts.isEmpty {
                        emptyState
                    } else {
                        monthlyPulse
                    }

                    Spacer(minLength: 144)
                }
                .padding(.horizontal, 34)
                .padding(.top, 36)
                .padding(.bottom, 26)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, minHeight: 340, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(cardStrokeColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var header: some View {
        Text("TRENDS")
            .font(.montserratBold(size: 12))
            .kerning(5)
            .foregroundStyle(accentColor)
    }

    private var monthlyPulse: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(formattedNumber(monthlyTotalMetric))
                    .font(.montserratBold(size: 54))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .shadow(color: .black.opacity(0.28), radius: 3, x: 0, y: 2)

                Text("steps this month")
                    .font(.montserratSemiBold(size: 17))
                    .foregroundStyle(secondaryTextColor)
            }

            comparisonLine
        }
    }
    
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("No trend yet")
                .font(.montserratBold(size: 30))
                .foregroundStyle(primaryTextColor)

            Text("Log a workout this month")
                .font(.montserratSemiBold(size: 14))
                .foregroundStyle(secondaryTextColor)
        }
    }

    private var comparisonLine: some View {
        HStack(spacing: 6) {
            if let volumeChange, abs(volumeChange) >= 1 {
                Image(systemName: volumeChange >= 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(comparisonColor(for: volumeChange))

                Text(formattedPercent(abs(volumeChange)))
                    .font(.montserratBold(size: 14))
                    .foregroundStyle(comparisonColor(for: volumeChange))

                Text("vs \(comparisonLabel)")
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(secondaryTextColor)
            } else if previousComparisonWorkouts.isEmpty {
                Text("New monthly baseline")
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(secondaryTextColor)
            } else {
                Text("Even vs \(comparisonLabel)")
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(secondaryTextColor)
            }
        }
    }

    private func formattedNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private func comparisonColor(for change: Double) -> Color {
        change >= 0 ? accentColor : .red
    }

    private func formattedPercent(_ value: Double) -> String {
        if value >= 1000 {
            return "999+%"
        }

        return "\(value.formatted(.number.precision(.fractionLength(0))))%"
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(cardBaseColor)
            .overlay(alignment: .bottomTrailing) {
                LinearGradient(
                    colors: [
                        accentColor.opacity(effectiveColorScheme == .dark ? 0.24 : 0.18),
                        .clear
                    ],
                    startPoint: .bottomTrailing,
                    endPoint: .topLeading
                )
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            }
            .overlay(alignment: .bottomLeading) {
                RadialGradient(
                    colors: [
                        accentColor.opacity(effectiveColorScheme == .dark ? 0.16 : 0.12),
                        .clear
                    ],
                    center: .bottomLeading,
                    startRadius: 30,
                    endRadius: 360
                )
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            }
    }

    private var cardBaseColor: Color {
        effectiveColorScheme == .dark
            ? Color(red: 0.035, green: 0.038, blue: 0.034)
            : Color(red: 0.045, green: 0.049, blue: 0.042)
    }

    private var cardStrokeColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.13) : .white.opacity(0.10)
    }

    private var primaryTextColor: Color {
        .white
    }

    private var secondaryTextColor: Color {
        .white.opacity(0.58)
    }

    private var accentColor: Color {
        .accentColor
    }

    private var comparisonLabel: String {
        guard let comparisonPreviousInterval else {
            return "last month"
        }

        guard isSelectedMonthCurrent,
              let previousEnd = calendar.date(byAdding: .day, value: -1, to: comparisonPreviousInterval.end)
        else {
            return previousMonthName
        }

        return "\(shortMonthDay(comparisonPreviousInterval.start))-\(calendar.component(.day, from: previousEnd))"
    }

    private var previousMonthName: String {
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: selectedDate) else {
            return "last month"
        }

        return previousMonth.formatted(.dateTime.month(.wide))
    }

    private func shortMonthDay(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}

private struct WorkoutTrendPreviewPoint: Identifiable {
    let id = UUID()
    let x: Double
    let y: Double
}

private struct WorkoutTrendPreviewSparkline: View {
    let points: [WorkoutTrendPreviewPoint]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let normalizedPoints = chartPoints(in: proxy.size)
            ZStack {
                if normalizedPoints.count >= 2 {
                    fillPath(points: normalizedPoints)
                        .fill(
                            LinearGradient(
                                colors: [
                                    color.opacity(0.19),
                                    color.opacity(0.045),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .mask {
                            fillFadeMask(points: normalizedPoints)
                        }

                    linePath(points: normalizedPoints)
                        .stroke(color.opacity(0.20), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                        .blur(radius: 7)

                    linePath(points: normalizedPoints)
                        .stroke(color.opacity(0.45), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        .blur(radius: 3)

                    linePath(points: normalizedPoints)
                        .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    if let lastPoint = normalizedPoints.last {
                        Circle()
                            .fill(color)
                            .frame(width: 7, height: 7)
                            .shadow(color: color.opacity(0.8), radius: 9)
                            .position(lastPoint)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func chartPoints(in size: CGSize) -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        let maxY = max(points.map(\.y).max() ?? 0, 1)
        let minY = min(points.map(\.y).min() ?? 0, 0)
        let yRange = max(maxY - minY, 1)
        let horizontalInset: CGFloat = 34
        let verticalInset: CGFloat = 34
        let drawableWidth = max(size.width - horizontalInset * 2, 1)
        let drawableHeight = max(size.height - verticalInset * 2, 1)

        return points.map { point in
            CGPoint(
                x: horizontalInset + CGFloat(point.x) * drawableWidth,
                y: verticalInset + (1 - CGFloat((point.y - minY) / yRange)) * drawableHeight
            )
        }
    }

    private func linePath(points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    private func fillPath(points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }

            let baseline = points.map(\.y).max() ?? last.y
            let verticalDrop = max(baseline - last.y, 0)
            let horizontalRun = max(last.x - first.x, 0)
            let cornerRadius = min(30, verticalDrop, horizontalRun)

            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }

            if cornerRadius > 0 {
                path.addLine(to: CGPoint(x: last.x, y: baseline - cornerRadius))
                path.addQuadCurve(
                    to: CGPoint(x: last.x - cornerRadius, y: baseline),
                    control: CGPoint(x: last.x, y: baseline)
                )
            } else {
                path.addLine(to: CGPoint(x: last.x, y: baseline))
            }

            path.addLine(to: CGPoint(x: first.x, y: baseline))
            path.addLine(to: first)
            path.closeSubpath()
        }
    }

    private func fillFadeMask(points: [CGPoint]) -> some View {
        GeometryReader { proxy in
            if let first = points.first, let last = points.last {
                let fadeWidth = min(max(last.x - first.x, 1) * 0.22, 72)
                let solidEnd = max(last.x - fadeWidth, first.x)

                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: max(solidEnd / proxy.size.width, 0)),
                        .init(color: .clear, location: min(last.x / proxy.size.width, 1))
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else {
                Color.clear
            }
        }
    }
}

struct WorkoutTrendChartView: View {
    let title: String
    let unitLabel: String
    let points: [WorkoutTrendPoint]
    let metricType: WorkoutTrendMetricType
    let colorScheme: ColorScheme

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = metricType == .stepsPerMinute ? 1 : 0
        formatter.minimumFractionDigits = 0
        return formatter
    }

    private var chartPoints: [ProgressLineChartPoint] {
        points.map { point in
            ProgressLineChartPoint(
                id: point.id.uuidString,
                date: point.date,
                value: point.value,
                valueText: "\(formattedValue(point.value)) \(unitLabel)",
                dateText: point.date.formatted(.dateTime.month(.abbreviated).day().year())
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.montserratSemiBold(size: 15))
                .foregroundStyle(colorScheme == .dark ? .white : .black)

            ProgressLineChartView(
                title: title,
                points: chartPoints,
                colorScheme: colorScheme,
                height: 300,
                xAxisStyle: .monthDay,
                yAxisLabel: { formattedValue($0) }
            )
        }
    }

    private func formattedValue(_ value: Double) -> String {
        formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }
}
