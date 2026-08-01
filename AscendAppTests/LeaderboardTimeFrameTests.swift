import Foundation
import Testing
@testable import AscendApp

struct LeaderboardTimeFrameTests {
    @Test
    func dailyPeriodsUseCanonicalUtcDayWindows() {
        let referenceDate = utcDate(year: 2026, month: 4, day: 5, hour: 18, minute: 30)
        let period = LeaderboardTimeFrame.daily.currentPeriod(referenceDate: referenceDate)

        #expect(period.key == "2026-04-05")
        #expect(period.startAt == utcDate(year: 2026, month: 4, day: 5))
        #expect(period.endAt == utcDate(year: 2026, month: 4, day: 6))
        #expect(period.contains(referenceDate, referenceDate: referenceDate))
        #expect(period.contains(utcDate(year: 2026, month: 4, day: 6), referenceDate: referenceDate) == false)
    }

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

    /// Pins the exact key strings every writer and reader agree on, against the same file
    /// the JavaScript halves read. The client (`currentPeriod`), the finalizer
    /// (`previousPeriod` in `functions/src/leaderboardAchievements.ts`), and the seeds
    /// (`currentPeriod` in `scripts/lib/leaderboard-period.mjs` and in
    /// `scripts/seed/fixtures/profile-fixtures.mjs`) all derive these independently; a
    /// document written under one spelling is invisible to a reader using another, and the
    /// board just looks empty.
    @Test
    func periodKeysMatchTheServerAndSeedDerivation() throws {
        let vector = try Self.sharedPeriodKeyVector()

        #expect(vector.cases.count >= 9)

        for testCase in vector.cases {
            let (year, month, day) = try Self.dateComponents(of: testCase)
            let referenceDate = utcDate(year: year, month: month, day: day, hour: 12)

            #expect(
                LeaderboardTimeFrame.weekly.currentPeriod(referenceDate: referenceDate).key
                    == testCase.weekly,
                "weekly key for \(testCase.date) - \(testCase.name)"
            )
            #expect(
                LeaderboardTimeFrame.monthly.currentPeriod(referenceDate: referenceDate).key
                    == testCase.monthly,
                "monthly key for \(testCase.date) - \(testCase.name)"
            )
            #expect(
                LeaderboardTimeFrame.yearly.currentPeriod(referenceDate: referenceDate).key
                    == testCase.yearly,
                "yearly key for \(testCase.date) - \(testCase.name)"
            )
        }
    }

    private struct PeriodKeyVectorFile: Decodable {
        struct Case: Decodable {
            let name: String
            let date: String
            let weekly: String
            let monthly: String
            let yearly: String
        }

        let cases: [Case]
    }

    private static func sharedPeriodKeyVector() throws -> PeriodKeyVectorFile {
        let repoRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let vectorURL = repoRoot.appending(
            path: "SharedTestVectors/leaderboard-period-key-vector.json"
        )
        let data = try Data(contentsOf: vectorURL)
        return try JSONDecoder().decode(PeriodKeyVectorFile.self, from: data)
    }

    private struct MalformedVectorDate: Error, CustomStringConvertible {
        let date: String
        var description: String { "vector date \(date) is not YYYY-MM-DD" }
    }

    private static func dateComponents(
        of testCase: PeriodKeyVectorFile.Case
    ) throws -> (year: Int, month: Int, day: Int) {
        let numbers = testCase.date.split(separator: "-").compactMap { Int($0) }
        guard numbers.count == 3 else { throw MalformedVectorDate(date: testCase.date) }
        return (numbers[0], numbers[1], numbers[2])
    }

    /// A week is *not* inside a month. On 2026-08-01 the weekly window opened on
    /// Jul 27, five days before the monthly window - so a populated weekly board sitting
    /// beside an empty monthly board is arithmetic, not data loss.
    ///
    /// This is pinned because the obvious "fix" for that screenshot is to force the two
    /// windows to nest, which would silently change what the weekly board measures.
    @Test
    func aWeeklyWindowCanOpenBeforeTheMonthlyWindowItOverlaps() {
        let firstOfMonth = utcDate(year: 2026, month: 8, day: 1, hour: 16, minute: 33)

        let weekly = LeaderboardTimeFrame.weekly.currentPeriod(referenceDate: firstOfMonth)
        let monthly = LeaderboardTimeFrame.monthly.currentPeriod(referenceDate: firstOfMonth)

        #expect(weekly.startAt < monthly.startAt)
        #expect(weekly.startAt == utcDate(year: 2026, month: 7, day: 27))
        #expect(monthly.startAt == utcDate(year: 2026, month: 8, day: 1))

        // A climb logged Jul 30 counts in the current week and not in the current month.
        let julyClimb = utcDate(year: 2026, month: 7, day: 30, hour: 1)
        #expect(weekly.contains(julyClimb, referenceDate: firstOfMonth))
        #expect(monthly.contains(julyClimb, referenceDate: firstOfMonth) == false)
    }

    /// Windows are canonical UTC, not device-local. Two devices in different zones on the
    /// same instant have to write and read the same document, so the boundary must land on
    /// UTC midnight even when that is mid-afternoon somewhere.
    @Test
    func periodWindowsAreAnchoredToUtcNotTheDeviceZone() {
        #expect(LeaderboardTimeFrame.canonicalTimeZone.secondsFromGMT() == 0)

        // 2026-08-03T01:00Z is Monday of W32 in UTC and still Sunday of W31 in Chicago.
        let instant = utcDate(year: 2026, month: 8, day: 3, hour: 1)
        let weekly = LeaderboardTimeFrame.weekly.currentPeriod(referenceDate: instant)

        #expect(weekly.key == "2026-W32")
        #expect(weekly.startAt == utcDate(year: 2026, month: 8, day: 3))
    }

    @Test
    func windowLabelsNameTheConcreteWindowTheBoardCovers() {
        let firstOfMonth = utcDate(year: 2026, month: 8, day: 1, hour: 16, minute: 33)

        // The inclusive last day, not the exclusive end: the window ends Sunday Aug 2,
        // and `endAt` is the Monday that belongs to the following week.
        #expect(
            LeaderboardTimeFrame.weekly.currentPeriod(referenceDate: firstOfMonth).windowLabel
                == "Jul 27 - Aug 2"
        )
        #expect(
            LeaderboardTimeFrame.monthly.currentPeriod(referenceDate: firstOfMonth).windowLabel
                == "August"
        )
        #expect(
            LeaderboardTimeFrame.yearly.currentPeriod(referenceDate: firstOfMonth).windowLabel
                == "2026"
        )
        #expect(
            LeaderboardTimeFrame.allTime.currentPeriod(referenceDate: firstOfMonth).windowLabel
                == "All time"
        )
    }

    /// The window is Gregorian by construction and stored under a Gregorian key, so its
    /// label has to be Gregorian too. Left on `Calendar.autoupdatingCurrent`, a device set
    /// to a Buddhist or Islamic calendar renders the board keyed `2026-M08` as "2569 BE"
    /// or "صفر" - a label contradicting its own key.
    @Test
    func windowLabelsAreFormattedInTheGregorianCalendarTheWindowIsDefinedIn() {
        let styles = [
            LeaderboardPeriod.dayStyle,
            LeaderboardPeriod.monthStyle,
            LeaderboardPeriod.yearStyle
        ]

        for style in styles {
            #expect(style.calendar.identifier == .gregorian)
            #expect(style.calendar == LeaderboardPeriod.labelCalendar)
            #expect(style.calendar != .autoupdatingCurrent)
            #expect(style.locale == LeaderboardPeriod.labelLocale)
            #expect(style.timeZone == LeaderboardTimeFrame.canonicalTimeZone)
        }

        // Proves the pin is load-bearing rather than incidental: the same styles on a
        // non-Gregorian calendar name a different month and year for the same instant.
        let firstOfMonth = utcDate(year: 2026, month: 8, day: 1, hour: 16, minute: 33)
        var buddhist = LeaderboardPeriod.yearStyle
        buddhist.calendar = Calendar(identifier: .buddhist)
        buddhist.locale = Locale(identifier: "th_TH")
        #expect(buddhist.format(firstOfMonth) != LeaderboardPeriod.yearStyle.format(firstOfMonth))

        var islamic = LeaderboardPeriod.monthStyle
        islamic.calendar = Calendar(identifier: .islamicUmmAlQura)
        islamic.locale = Locale(identifier: "ar_SA")
        #expect(islamic.format(firstOfMonth) != LeaderboardPeriod.monthStyle.format(firstOfMonth))

        #expect(
            LeaderboardTimeFrame.monthly.currentPeriod(referenceDate: firstOfMonth).windowLabel
                == "August"
        )
        #expect(
            LeaderboardTimeFrame.yearly.currentPeriod(referenceDate: firstOfMonth).windowLabel
                == "2026"
        )
    }

    @Test
    func windowSubjectsReadAsSentenceSubjectsForEmptyStateCopy() {
        let firstOfMonth = utcDate(year: 2026, month: 8, day: 1, hour: 16, minute: 33)

        #expect(
            LeaderboardTimeFrame.monthly.currentPeriod(referenceDate: firstOfMonth).windowSubject
                == "August"
        )
        #expect(
            LeaderboardTimeFrame.weekly.currentPeriod(referenceDate: firstOfMonth).windowSubject
                == "This week"
        )
        #expect(
            LeaderboardTimeFrame.allTime.currentPeriod(referenceDate: firstOfMonth).windowSubject
                == "This board"
        )
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
