import SwiftUI

/// The one line Home's sheet collapses to: this week's climbs and steps, the same
/// numbers `ThisWeekCard` reads, on one line and without a chart.
struct HomeThisWeekLine: View {
    /// This week's summary from `HomeDashboardViewModel`; nil before the first
    /// refresh reads as a week with nothing in it yet.
    let summary: WeekActivitySummary?

    var body: some View {
        let summary = self.summary ?? Self.emptySummary

        HStack(alignment: .center, spacing: 10) {
            Text("THIS WEEK")
                .font(.montserratBold(size: 10))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(1)

            Text(Self.lineText(for: summary))
                .font(.montserratSemiBold(size: 13))
                .foregroundStyle(.white.opacity(summary.weekWorkoutCount > 0 ? 0.92 : 0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 0)
        }
        .frame(height: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week: \(Self.lineText(for: summary))")
    }

    private static let emptySummary = WeekActivitySummaryCalculator(
        workouts: [],
        firstWeekday: WeekConfiguration.mondayFirstWeekday
    ).calculate()

    /// "0 climbs · 0 steps" on a quiet week: the zeros are the fact, stated as zeros.
    static func lineText(for summary: WeekActivitySummary) -> String {
        let climbs = "\(summary.weekWorkoutCount) \(summary.weekWorkoutCount == 1 ? "climb" : "climbs")"
        let steps = "\(WeekActivityFormat.compactValue(summary.weekTotalValue)) steps"
        return "\(climbs) · \(steps)"
    }
}
