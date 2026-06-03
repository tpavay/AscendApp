import Foundation
import Testing
@testable import AscendApp

struct DailyClimbRecommendationPolicyTests {
    @Test
    func dayKeyUsesPreviousCalendarDayBeforeFourAM() throws {
        let calendar = utcCalendar
        let date = try #require(date(year: 2026, month: 1, day: 2, hour: 3, minute: 59, calendar: calendar))

        let key = DailyClimbRecommendationPolicy.dayKey(for: date, calendar: calendar)

        #expect(key == "2026-01-01")
    }

    @Test
    func dayKeyUsesCurrentCalendarDayAtFourAM() throws {
        let calendar = utcCalendar
        let date = try #require(date(year: 2026, month: 1, day: 2, hour: 4, minute: 0, calendar: calendar))

        let key = DailyClimbRecommendationPolicy.dayKey(for: date, calendar: calendar)

        #expect(key == "2026-01-02")
    }

    @Test
    func nextRolloverIsTodayWhenBeforeFourAM() throws {
        let calendar = utcCalendar
        let date = try #require(date(year: 2026, month: 1, day: 2, hour: 3, minute: 0, calendar: calendar))
        let expected = try #require(date(year: 2026, month: 1, day: 2, hour: 4, minute: 0, calendar: calendar))

        let rollover = DailyClimbRecommendationPolicy.nextRolloverDate(after: date, calendar: calendar)

        #expect(rollover == expected)
    }

    @Test
    func nextRolloverIsTomorrowWhenAtFourAM() throws {
        let calendar = utcCalendar
        let date = try #require(date(year: 2026, month: 1, day: 2, hour: 4, minute: 0, calendar: calendar))
        let expected = try #require(date(year: 2026, month: 1, day: 3, hour: 4, minute: 0, calendar: calendar))

        let rollover = DailyClimbRecommendationPolicy.nextRolloverDate(after: date, calendar: calendar)

        #expect(rollover == expected)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date? {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ).date
    }
}
