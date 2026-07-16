import Charts
import SwiftUI

/// Interactive weekly steps trend — a smooth gradient curve of weekly step totals across the
/// last several Monday-based weeks. The header + Steps / Duration / Avg SPM metrics reflect the
/// selected week (defaulting to this week). Faint vertical gridlines mark each tappable week;
/// tapping one selects it and the selection persists until another week is tapped.
struct ProfileWeeklyStepsChart: View {
    let workouts: [ProfileWorkoutSummary]

    @State private var selectedWeekStart: Date?

    private static let weekCount = 12

    var body: some View {
        let weeks = Self.weeklySteps(from: workouts, now: Date())
        let displayed = Self.displayedWeek(in: weeks, selectedWeekStart: selectedWeekStart)
        let hasData = weeks.contains { $0.steps > 0 }

        VStack(alignment: .leading, spacing: 14) {
            header(for: displayed, weeks: weeks)

            if hasData {
                metricsRow(for: displayed)
                chart(weeks: weeks, displayed: displayed)
            } else {
                emptyState
            }
        }
    }

    private func header(for displayed: WeekStepsPoint?, weeks: [WeekStepsPoint]) -> some View {
        let label: String
        if let displayed, displayed.id != weeks.last?.id {
            label = displayed.rangeLabel
        } else {
            label = "THIS WEEK"
        }

        return Text(label)
            .font(.montserratBold(size: 16))
            .foregroundStyle(.white)
            .tracking(1.4)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 2)
            .animation(.easeInOut(duration: 0.15), value: label)
    }

    private func metricsRow(for displayed: WeekStepsPoint?) -> some View {
        let spm = displayed?.averageStepsPerMinute ?? 0
        return HStack(alignment: .top, spacing: 10) {
            metric(value: "\(displayed?.climbs ?? 0)", label: "Climbs")
            metric(value: Self.compact(displayed?.steps ?? 0), label: "Steps")
            metric(value: Self.durationText(displayed?.durationSeconds ?? 0), label: "Duration")
            metric(value: spm > 0 ? "\(Int(spm.rounded()))" : "—", label: "Avg SPM")
        }
        .padding(.horizontal, 2)
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.montserratMedium(size: 11))
                .foregroundStyle(ProfileVisualStyle.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(value)
                .font(.montserratBold(size: 18))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chart(weeks: [WeekStepsPoint], displayed: WeekStepsPoint?) -> some View {
        let yMax = max(Int(Double(weeks.map(\.steps).max() ?? 0) * 1.25), 10)

        return Chart {
            ForEach(weeks) { week in
                AreaMark(
                    x: .value("Week", week.weekStart),
                    y: .value("Steps", week.steps)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.ascendAccent.opacity(0.32), Color.ascendAccent.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Week", week.weekStart),
                    y: .value("Steps", week.steps)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.ascendAccent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }

            if let displayed {
                if selectedWeekStart != nil {
                    RuleMark(x: .value("Week", displayed.weekStart))
                        .foregroundStyle(.white.opacity(0.28))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }

                PointMark(
                    x: .value("Week", displayed.weekStart),
                    y: .value("Steps", displayed.steps)
                )
                .foregroundStyle(.white)
                .symbolSize(56)
            }
        }
        .chartYScale(domain: 0...yMax)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: weeks.map(\.weekStart)) { _ in
                AxisGridLine()
                    .foregroundStyle(.white.opacity(0.08))
            }
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated))
                    .font(.montserratMedium(size: 10))
                    .foregroundStyle(ProfileVisualStyle.tertiaryText)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let xPosition = value.location.x - geo[plotFrame].origin.x
                                guard let date: Date = proxy.value(atX: xPosition, as: Date.self) else { return }
                                selectedWeekStart = Self.nearestWeekStart(to: date, in: weeks)
                            }
                    )
            }
        }
        .frame(height: 150)
    }

    private var emptyState: some View {
        Text("No climbs logged yet. Your weekly trend starts with your first session.")
            .font(.montserratMedium(size: 13))
            .foregroundStyle(ProfileVisualStyle.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
            .padding(.horizontal, 2)
    }

    // MARK: - Aggregation

    private static func displayedWeek(in weeks: [WeekStepsPoint], selectedWeekStart: Date?) -> WeekStepsPoint? {
        guard !weeks.isEmpty else { return nil }
        if let selectedWeekStart, let match = weeks.first(where: { $0.weekStart == selectedWeekStart }) {
            return match
        }
        return weeks.last
    }

    private static func nearestWeekStart(to date: Date, in weeks: [WeekStepsPoint]) -> Date? {
        weeks.min {
            abs($0.weekStart.timeIntervalSince(date)) < abs($1.weekStart.timeIntervalSince(date))
        }?.weekStart
    }

    /// Buckets workout steps + duration into the trailing `weekCount` Monday-based weeks.
    private static func weeklySteps(from workouts: [ProfileWorkoutSummary], now: Date) -> [WeekStepsPoint] {
        let calendar = Calendar.current

        func mondayStart(of date: Date) -> Date? {
            let day = calendar.startOfDay(for: date)
            let weekday = calendar.component(.weekday, from: day)
            let daysFromMonday = (weekday + 5) % 7
            return calendar.date(byAdding: .day, value: -daysFromMonday, to: day)
        }

        guard let thisMonday = mondayStart(of: now) else { return [] }

        var weekStarts: [Date] = []
        var buckets: [Date: (climbs: Int, steps: Int, duration: Int)] = [:]
        for offset in stride(from: weekCount - 1, through: 0, by: -1) {
            guard let start = calendar.date(byAdding: .day, value: -7 * offset, to: thisMonday) else { continue }
            weekStarts.append(start)
            buckets[start] = (0, 0, 0)
        }

        guard let earliest = weekStarts.first else { return [] }

        for workout in workouts {
            let day = calendar.startOfDay(for: workout.startedAt)
            guard day >= earliest, let start = mondayStart(of: day), buckets[start] != nil else { continue }
            buckets[start]?.climbs += 1
            buckets[start]?.steps += workout.steps
            buckets[start]?.duration += Int(workout.durationSeconds)
        }

        return weekStarts.map { start in
            let bucket = buckets[start] ?? (0, 0, 0)
            return WeekStepsPoint(
                weekStart: start,
                climbs: bucket.climbs,
                steps: bucket.steps,
                durationSeconds: bucket.duration
            )
        }
    }

    private static func compact(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 10_000 {
            return String(format: "%.1fk", Double(value) / 1_000)
        }
        return value.formatted(.number.grouping(.automatic))
    }

    private static func durationText(_ seconds: Int) -> String {
        guard seconds > 0 else { return "0m" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }
}

private struct WeekStepsPoint: Identifiable, Equatable {
    let weekStart: Date
    let climbs: Int
    let steps: Int
    let durationSeconds: Int

    var id: Date { weekStart }

    var averageStepsPerMinute: Double {
        let minutes = Double(durationSeconds) / 60
        return minutes > 0 ? Double(steps) / minutes : 0
    }

    var rangeLabel: String {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let startText = weekStart.formatted(.dateTime.month(.abbreviated).day())
        let endText = end.formatted(.dateTime.month(.abbreviated).day())
        return "\(startText) – \(endText)".uppercased()
    }
}
