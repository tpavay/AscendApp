import Foundation
import Testing
@testable import AscendApp

struct SeasonalThemeTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test
    func theWindowsAreNovemberDecemberJanuaryAndOctober() {
        #expect(SeasonalTheme.active(on: date(2026, 11, 1, hour: 0), calendar: calendar) == .november)
        #expect(SeasonalTheme.active(on: date(2026, 11, 30, hour: 23), calendar: calendar) == .november)
        #expect(SeasonalTheme.active(on: date(2026, 12, 1, hour: 0), calendar: calendar) == .december)
        #expect(SeasonalTheme.active(on: date(2026, 12, 31, hour: 23), calendar: calendar) == .december)
        #expect(SeasonalTheme.active(on: date(2027, 1, 1, hour: 0), calendar: calendar) == .newYear)
        #expect(SeasonalTheme.active(on: date(2027, 1, 31, hour: 23), calendar: calendar) == .newYear)
        #expect(SeasonalTheme.active(on: date(2026, 10, 1, hour: 0), calendar: calendar) == .october)
        #expect(SeasonalTheme.active(on: date(2026, 10, 31, hour: 23), calendar: calendar) == .october)
    }

    @Test
    func everyOtherMonthHasNoTheme() {
        for month in [2, 3, 4, 5, 6, 7, 8, 9] {
            #expect(SeasonalTheme.active(on: date(2027, month, 15), calendar: calendar) == nil)
        }
    }

    @Test
    func newYearsStartsAtMidnightOnJanuaryFirstNotOnDecemberTwentySixth() {
        #expect(SeasonalTheme.active(on: date(2026, 12, 26), calendar: calendar) == .december)
        #expect(SeasonalTheme.active(on: date(2026, 12, 31, hour: 23), calendar: calendar) == .december)
        #expect(SeasonalTheme.active(on: date(2027, 1, 1, hour: 0), calendar: calendar) == .newYear)
    }

    @Test
    func theWindowFollowsTheClimbersLocalDate() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        // 23:30 on Oct 31 in New York is already November 1 in Tokyo.
        let instant = date(2026, 10, 31, hour: 23)
        #expect(SeasonalTheme.active(on: instant, calendar: calendar) == .october)
        #expect(SeasonalTheme.active(on: instant, calendar: tokyo) == .november)
    }

    @Test
    func theYearInNewYearCopyIsGeneratedFromTheDate() {
        #expect(SeasonalTheme.copyYear(on: date(2027, 1, 3), calendar: calendar) == 2027)
        #expect(SeasonalTheme.copyYear(on: date(2031, 1, 3), calendar: calendar) == 2031)
        #expect(SeasonalBackground.confetti.caption(year: 2031) == "FIRST CLIMB OF 2031")
    }

    @Test
    func aSeasonalBackgroundIsOfferedOnlyInItsWindow() {
        let november = SeasonalBackground.available(on: date(2026, 11, 10), calendar: calendar)
        #expect(november == [.leafFall, .flannel])
        #expect(SeasonalBackground.available(on: date(2027, 3, 10), calendar: calendar).isEmpty)

        #expect(SeasonalBackground.snowfall.isAvailable(on: date(2026, 12, 20), calendar: calendar))
        #expect(!SeasonalBackground.snowfall.isAvailable(on: date(2027, 1, 2), calendar: calendar))
    }

    @Test
    func theApprovedSetIsTwelveBackgroundsAcrossFourThemes() {
        #expect(SeasonalBackground.allCases.count == 12)
        for theme in SeasonalTheme.allCases {
            #expect(SeasonalBackground.allCases.contains { $0.theme == theme })
        }
        #expect(SeasonalBackground.available(on: date(2026, 12, 5), calendar: calendar).count == 5)
        #expect(SeasonalBackground.available(on: date(2027, 1, 5), calendar: calendar).count == 4)
    }
}
