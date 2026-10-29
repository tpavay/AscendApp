import Foundation
import Testing
@testable import AscendApp

struct ShareTotalsBuilderTests {
    private var calendar: Calendar {
        WeekConfiguration.calendar(timeZone: TimeZone(identifier: "UTC")!)
    }

    /// Wednesday, October 28, 2026, noon UTC. The week runs Monday the 26th to Sunday the 1st.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 12))!
    }

    private func sample(_ month: Int, _ day: Int, steps: Int, minutes: Double = 30, year: Int = 2026) -> ShareTotalsBuilder.Sample {
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 8))!
        return ShareTotalsBuilder.Sample(date: date, steps: steps, duration: minutes * 60)
    }

    @Test
    func theWeekSumsMondayThroughSunday() {
        let samples = [
            sample(10, 25, steps: 999),
            sample(10, 26, steps: 2_000),
            sample(10, 28, steps: 3_000),
            sample(11, 1, steps: 500),
            sample(11, 2, steps: 777)
        ]
        let snapshot = ShareTotalsBuilder.make(samples: samples, period: .week, now: now, calendar: calendar)

        #expect(snapshot.steps == 5_500)
        #expect(snapshot.climbs == 3)
        #expect(snapshot.periodCaption == "THIS WEEK")
        #expect(snapshot.weekDays == [true, false, true, false, false, false, true])
    }

    @Test
    func floorsAreStepsDividedBySixteenOverThePeriodsTotal() {
        let samples = [sample(10, 26, steps: 1_000), sample(10, 27, steps: 1_000)]
        let snapshot = ShareTotalsBuilder.make(samples: samples, period: .week, now: now, calendar: calendar)
        #expect(snapshot.floors == 125)
    }

    @Test
    func theMonthAndYearWindowsFollowTheCalendar() {
        let samples = [
            sample(1, 5, steps: 1_000),
            sample(9, 30, steps: 2_000),
            sample(10, 1, steps: 3_000),
            sample(10, 28, steps: 4_000)
        ]
        let month = ShareTotalsBuilder.make(samples: samples, period: .month, now: now, calendar: calendar)
        #expect(month.steps == 7_000)
        #expect(month.periodCaption == "THIS MONTH")

        let year = ShareTotalsBuilder.make(samples: samples, period: .year, now: now, calendar: calendar)
        #expect(year.steps == 10_000)
        #expect(year.climbs == 4)
    }

    @Test
    func theCalendarIsTheCurrentMonthStartingOnMonday() {
        let samples = [sample(10, 3, steps: 100), sample(10, 3, steps: 100), sample(10, 28, steps: 100)]
        let snapshot = ShareTotalsBuilder.make(samples: samples, period: .week, now: now, calendar: calendar)

        #expect(snapshot.calendarMonthName == "OCTOBER")
        #expect(snapshot.calendarDayCount == 31)
        // October 1, 2026 is a Thursday: three blanks in a Monday-first grid.
        #expect(snapshot.calendarLeadingBlanks == 3)
        #expect(snapshot.calendarClimbDays == [3, 28])
        #expect(snapshot.calendarClimbCount == 3)
    }

    @Test
    func theSixWeeklyBarsEndWithTheCurrentWeek() {
        let samples = [
            sample(9, 21, steps: 111),
            sample(10, 5, steps: 222),
            sample(10, 26, steps: 333)
        ]
        let bars = ShareTotalsBuilder.weeklySteps(samples: samples, now: now, calendar: calendar)
        #expect(bars.count == 6)
        #expect(bars.last == 333)
        #expect(bars[2] == 222)
        #expect(bars[0] == 111)
    }

    @Test
    func theThirtyDayPaceIsTotalStepsOverTotalMinutes() {
        let samples = [
            sample(10, 20, steps: 2_400, minutes: 30),
            sample(10, 27, steps: 1_200, minutes: 30),
            sample(8, 1, steps: 9_999, minutes: 30)
        ]
        let pace = ShareTotalsBuilder.averagePace(samples: samples, now: now, calendar: calendar)
        #expect(pace == 60)
    }

    @Test
    func noClimbsMeansNoPaceAndAnEmptyWeek() {
        let snapshot = ShareTotalsBuilder.make(samples: [], period: .week, now: now, calendar: calendar)
        #expect(snapshot.averagePace30Days == nil)
        #expect(!snapshot.hasClimbs)
        #expect(snapshot.weekDays == Array(repeating: false, count: 7))
        #expect(snapshot.weeklySteps == Array(repeating: 0, count: 6))
    }

    @Test
    func aStandingReadsTopPercentAndTheBeatFraction() throws {
        let standing = try #require(ShareTotalsSnapshot.Standing(position: 3, field: 120))
        #expect(standing.positionText == "#3")
        #expect(standing.topPercent == 3)
        #expect(abs(standing.beatFraction - 117.0 / 120.0) < 1e-9)
        #expect(ShareTotalsSnapshot.Standing(position: nil, field: 120) == nil)
    }

    @Test
    func aLargeTotalsStandingGroupsItsDigits() throws {
        let standing = try #require(ShareTotalsSnapshot.Standing(position: 12_345, field: 20_000))
        #expect(standing.positionText == "#12,345")
        #expect(standing.headline == "#12,345")
    }

    @Test
    func theEarliestNeededDateCoversTheYearTheBarsAndThePaceWindow() {
        let earliest = ShareTotalsBuilder.earliestNeededDate(now: now, calendar: calendar)
        let yearStart = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        #expect(earliest == yearStart)

        // Early in January the six weekly bars reach back into the previous year.
        let january = calendar.date(from: DateComponents(year: 2027, month: 1, day: 12, hour: 12))!
        let januaryEarliest = ShareTotalsBuilder.earliestNeededDate(now: january, calendar: calendar)
        #expect(januaryEarliest < calendar.date(from: DateComponents(year: 2027, month: 1, day: 1))!)
    }
}
