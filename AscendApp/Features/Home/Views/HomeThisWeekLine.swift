import SwiftUI

/// The one line Home's sheet collapses to: this week's climbs, steps and time, with
/// the week's bars beside them. The same numbers `ThisWeekCard` reads, on one line.
struct HomeThisWeekLine: View {
    let workouts: [Workout]

    private var summary: WeekActivitySummary {
        WeekActivitySummaryCalculator(
            workouts: workouts,
            firstWeekday: WeekConfiguration.mondayFirstWeekday
        ).calculate()
    }

    var body: some View {
        let summary = self.summary

        HStack(alignment: .center, spacing: 10) {
            Text("THIS WEEK")
                .font(.montserratBold(size: 10))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(1)

            Text(Self.lineText(for: summary))
                .font(.montserratSemiBold(size: 13))
                .foregroundStyle(.white.opacity(summary.weekWorkoutCount > 0 ? 0.92 : 0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 6)

            MiniWeekBarChart(
                data: summary.dailyBars,
                hasData: summary.weekWorkoutCount > 0
            )
            .frame(width: 96, height: 28)
        }
        .frame(height: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week: \(Self.lineText(for: summary))")
    }

    static func lineText(for summary: WeekActivitySummary) -> String {
        guard summary.weekWorkoutCount > 0 else {
            return "No climbs yet"
        }
        let climbs = "\(summary.weekWorkoutCount) \(summary.weekWorkoutCount == 1 ? "climb" : "climbs")"
        let steps = "\(WeekActivityFormat.compactValue(summary.weekTotalValue)) steps"
        let time = WeekActivityFormat.compactDuration(summary.totalDuration)
        return "\(climbs) · \(steps) · \(time)"
    }
}
