import Foundation
import Testing
@testable import AscendApp

struct WeeklyStreakTests {
    private static let chicago = TimeZone(identifier: "America/Chicago")!
    private let calendar = WeekConfiguration.calendar(timeZone: WeeklyStreakTests.chicago)

    @Test
    func aClimbThisWeekCountsAndSecuresTheStreak() {
        // Wednesday, with climbs this week and in each of the two weeks before.
        let streak = WeeklyStreak.current(
            climbDates: [local(2026, 9, 23), local(2026, 9, 16), local(2026, 9, 8)],
            referenceDate: local(2026, 9, 23, hour: 20),
            calendar: calendar
        )

        #expect(streak == WeeklyStreak(weeks: 3, isCurrentWeekSecured: true))
    }

    @Test
    func aWeekNotYetClimbedKeepsTheStreakAliveButUnsecured() {
        // Wednesday, nothing yet this week, climbs in each of the two weeks before.
        let streak = WeeklyStreak.current(
            climbDates: [local(2026, 9, 16), local(2026, 9, 8)],
            referenceDate: local(2026, 9, 23, hour: 20),
            calendar: calendar
        )

        #expect(streak == WeeklyStreak(weeks: 2, isCurrentWeekSecured: false))
    }

    @Test
    func aWholeWeekWithoutAClimbBreaksTheStreak() {
        // Nothing last week and nothing yet this week: the run two weeks back is over.
        let broken = WeeklyStreak.current(
            climbDates: [local(2026, 9, 9), local(2026, 9, 2)],
            referenceDate: local(2026, 9, 23, hour: 20),
            calendar: calendar
        )
        #expect(broken == .none)

        // A gap behind this week's climb restarts the count at this week.
        let restarted = WeeklyStreak.current(
            climbDates: [local(2026, 9, 22), local(2026, 9, 9), local(2026, 9, 2)],
            referenceDate: local(2026, 9, 23, hour: 20),
            calendar: calendar
        )
        #expect(restarted == WeeklyStreak(weeks: 1, isCurrentWeekSecured: true))
    }

    @Test
    func theFirstClimbStartsAOneWeekStreak() {
        #expect(
            WeeklyStreak.current(climbDates: [], referenceDate: local(2026, 9, 23), calendar: calendar) == .none
        )
        #expect(
            WeeklyStreak.current(
                climbDates: [local(2026, 9, 21, hour: 7)],
                referenceDate: local(2026, 9, 21, hour: 8),
                calendar: calendar
            ) == WeeklyStreak(weeks: 1, isCurrentWeekSecured: true)
        )
    }

    /// The production shape behind this fix: climbs Monday to Sunday of one week, none the
    /// week before, read on the Sunday. A Sunday-first locale week split that one week in two
    /// and reported "2 weeks in a row" with the week unsecured.
    @Test
    func sundayBelongsToTheMondayWeekWhateverTheDeviceLocale() {
        let climbs = [
            local(2026, 9, 22, hour: 7), local(2026, 9, 23, hour: 8), local(2026, 9, 25, hour: 7),
            local(2026, 9, 26, hour: 10), local(2026, 9, 27, hour: 9), local(2026, 9, 10, hour: 8),
        ]
        let sundayEvening = local(2026, 9, 27, hour: 15)

        #expect(
            WeeklyStreak.current(climbDates: climbs, referenceDate: sundayEvening, calendar: calendar)
                == WeeklyStreak(weeks: 1, isCurrentWeekSecured: true)
        )

        // The default calendar is the app's Monday week, not `Calendar.current`.
        var sundayFirst = Calendar(identifier: .gregorian)
        sundayFirst.timeZone = Self.chicago
        sundayFirst.firstWeekday = 1
        #expect(WeekConfiguration.calendar(timeZone: Self.chicago).firstWeekday == 2)
        #expect(
            WeeklyStreak.current(climbDates: climbs, referenceDate: sundayEvening, calendar: sundayFirst).weeks == 2,
            "A Sunday-first week reproduces the shipped miscount"
        )
    }

    @Test
    func weekBoundariesFollowTheClimbersOwnTimeZone() {
        // 23:30 Sunday in Chicago is already Monday in UTC; it still belongs to the week it
        // was climbed in, so on the next Wednesday the streak waits on that week.
        let lateSunday = local(2026, 9, 27, hour: 23, minute: 30)
        let streak = WeeklyStreak.current(
            climbDates: [lateSunday],
            referenceDate: local(2026, 9, 30, hour: 12),
            calendar: calendar
        )

        #expect(streak == WeeklyStreak(weeks: 1, isCurrentWeekSecured: false))
    }

    @Test
    func weeksAcrossADaylightSavingChangeStayConsecutive() {
        // US clocks fall back on Sunday 2026-11-01.
        let climbs = [local(2026, 10, 27), local(2026, 11, 3), local(2026, 11, 10)]

        #expect(
            WeeklyStreak.current(climbDates: climbs, referenceDate: local(2026, 11, 11), calendar: calendar)
                == WeeklyStreak(weeks: 3, isCurrentWeekSecured: true)
        )
        #expect(WeeklyStreak.longest(climbDates: climbs, calendar: calendar) == 3)
    }

    @Test
    func aClimbDatedAfterThisWeekDoesNotCount() {
        let streak = WeeklyStreak.current(
            climbDates: [local(2026, 10, 5)],
            referenceDate: local(2026, 9, 23),
            calendar: calendar
        )

        #expect(streak == .none)
    }

    @Test
    func longestFindsTheLongestRunAnywhereInHistory() {
        let climbs = [
            local(2026, 8, 4), local(2026, 8, 11), local(2026, 8, 18), local(2026, 8, 19),
            local(2026, 9, 8), local(2026, 9, 22),
        ]

        #expect(WeeklyStreak.longest(climbDates: climbs, calendar: calendar) == 3)
        #expect(WeeklyStreak.longest(climbDates: [], calendar: calendar) == 0)
        #expect(WeeklyStreak.longest(climbDates: [local(2026, 9, 22)], calendar: calendar) == 1)
    }

    private func local(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
