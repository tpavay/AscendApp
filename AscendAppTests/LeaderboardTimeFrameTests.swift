import Foundation
import Testing
@testable import AscendApp

struct LeaderboardTimeFrameTests {
    @Test
    func weeklyPeriodsUseMondayUtcWindows() {
        let referenceDate = utcDate(year: 2026, month: 4, day: 5, hour: 18, minute: 30)
        let period = LeaderboardTimeFrame.weekly.currentPeriod(referenceDate: referenceDate)

        #expect(period.startAt == utcDate(year: 2026, month: 3, day: 30))
        #expect(period.endAt == utcDate(year: 2026, month: 4, day: 6))
        #expect(period.contains(referenceDate, referenceDate: referenceDate))
        #expect(period.contains(utcDate(year: 2026, month: 4, day: 6), referenceDate: referenceDate) == false)
    }

    @Test
    func monthlyAndYearlyPeriodsUseCanonicalUtcBoundaries() {
        let referenceDate = utcDate(year: 2026, month: 4, day: 5, hour: 18, minute: 30)

        let monthly = LeaderboardTimeFrame.monthly.currentPeriod(referenceDate: referenceDate)
        #expect(monthly.key == "2026-M04")
        #expect(monthly.startAt == utcDate(year: 2026, month: 4, day: 1))
        #expect(monthly.endAt == utcDate(year: 2026, month: 5, day: 1))

        let yearly = LeaderboardTimeFrame.yearly.currentPeriod(referenceDate: referenceDate)
        #expect(yearly.key == "2026")
        #expect(yearly.startAt == utcDate(year: 2026, month: 1, day: 1))
        #expect(yearly.endAt == utcDate(year: 2027, month: 1, day: 1))
    }

    @Test
    func allTimeWindowEndsAtReferenceDateOnly() {
        let referenceDate = utcDate(year: 2026, month: 4, day: 5, hour: 18, minute: 30)
        let period = LeaderboardTimeFrame.allTime.currentPeriod(referenceDate: referenceDate)

        #expect(period.key == "all")
        #expect(period.startAt == Date(timeIntervalSince1970: 0))
        #expect(period.endAt == nil)
        #expect(period.contains(referenceDate, referenceDate: referenceDate))
        #expect(period.contains(referenceDate.addingTimeInterval(1), referenceDate: referenceDate) == false)
    }

    private func utcDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = WeekConfiguration.calendar(timeZone: LeaderboardTimeFrame.canonicalTimeZone)
        components.timeZone = LeaderboardTimeFrame.canonicalTimeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }
}
