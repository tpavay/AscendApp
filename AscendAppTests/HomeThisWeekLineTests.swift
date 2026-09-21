import Foundation
import Testing
@testable import AscendApp

/// The one line Home collapses to, from the same week summary `ThisWeekCard` reads.
@MainActor
struct HomeThisWeekLineTests {
    @Test
    func theLineCountsThisWeeksClimbsStepsAndTime() throws {
        let calendar = WeekConfiguration.calendar()
        let today = calendar.startOfDay(for: Date())
        let weekStart = try #require(calendar.dateInterval(of: .weekOfYear, for: today)?.start)
        let workouts = [
            workout(on: weekStart, steps: 1_850, minutes: 22),
            workout(on: today, steps: 2_143, minutes: 38),
            workout(on: calendar.date(byAdding: .day, value: -8, to: today)!, steps: 5_000, minutes: 60),
        ]

        let summary = WeekActivitySummaryCalculator(
            workouts: workouts,
            firstWeekday: WeekConfiguration.mondayFirstWeekday
        ).calculate()

        #expect(HomeThisWeekLine.lineText(for: summary) == "2 climbs · 4k steps")
    }

    @Test
    func anEmptyWeekStatesItsZeros() {
        let summary = WeekActivitySummaryCalculator(workouts: [], firstWeekday: WeekConfiguration.mondayFirstWeekday).calculate()
        #expect(HomeThisWeekLine.lineText(for: summary) == "0 climbs · 0 steps")
    }

    @Test
    func oneClimbIsSingular() throws {
        let today = WeekConfiguration.calendar().startOfDay(for: Date())
        let summary = WeekActivitySummaryCalculator(
            workouts: [workout(on: today, steps: 750, minutes: 10)],
            firstWeekday: WeekConfiguration.mondayFirstWeekday
        ).calculate()
        #expect(HomeThisWeekLine.lineText(for: summary) == "1 climb · 750 steps")
    }

    @Test
    func compactFormatsReadAtAGlance() {
        #expect(WeekActivityFormat.compactValue(750) == "750")
        #expect(WeekActivityFormat.compactValue(7_000) == "7k")
        #expect(WeekActivityFormat.compactValue(107_500) == "107.5k")
        #expect(WeekActivityFormat.compactDuration(48 * 60) == "48m")
        #expect(WeekActivityFormat.compactDuration(96 * 60) == "1.6h")
        #expect(WeekActivityFormat.compactDuration(2 * 3_600) == "2h")
    }

    private func workout(on date: Date, steps: Int, minutes: Int) -> Workout {
        Workout(
            name: "Climb",
            date: date,
            duration: TimeInterval(minutes * 60),
            steps: steps,
            floors: steps / 20,
            source: .headphoneMotion
        )
    }
}
