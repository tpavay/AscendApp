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

    /// Pins the exact key strings every writer and reader agree on. The client
    /// (`currentPeriod`), the finalizer (`previousPeriod` in
    /// `functions/src/leaderboardAchievements.ts`), and the seeds
    /// (`currentPeriod` in `scripts/seed-demo-user.mjs`) all derive these
    /// independently; a document written under one spelling is invisible to a reader
    /// using another, and the board just looks empty.
    @Test(arguments: PeriodKeyVector.all)
    func periodKeysMatchTheServerAndSeedDerivation(vector: PeriodKeyVector) {
        let referenceDate = utcDate(
            year: vector.year,
            month: vector.month,
            day: vector.day,
            hour: 12
        )

        #expect(LeaderboardTimeFrame.weekly.currentPeriod(referenceDate: referenceDate).key == vector.weekly)
        #expect(LeaderboardTimeFrame.monthly.currentPeriod(referenceDate: referenceDate).key == vector.monthly)
        #expect(LeaderboardTimeFrame.yearly.currentPeriod(referenceDate: referenceDate).key == vector.yearly)
    }

    struct PeriodKeyVector: Sendable, CustomStringConvertible {
        let year: Int
        let month: Int
        let day: Int
        let weekly: String
        let monthly: String
        let yearly: String

        var description: String { "\(year)-\(month)-\(day)" }

        static let all: [PeriodKeyVector] = [
            // The day the captain photographed the boards.
            .init(year: 2026, month: 8, day: 1, weekly: "2026-W31", monthly: "2026-M08", yearly: "2026"),
            .init(year: 2026, month: 7, day: 27, weekly: "2026-W31", monthly: "2026-M07", yearly: "2026"),
            .init(year: 2026, month: 8, day: 2, weekly: "2026-W31", monthly: "2026-M08", yearly: "2026"),
            .init(year: 2026, month: 8, day: 3, weekly: "2026-W32", monthly: "2026-M08", yearly: "2026"),
            // Single-digit week and month stay zero padded, or the key stops sorting
            // and stops matching what the server wrote.
            .init(year: 2026, month: 2, day: 5, weekly: "2026-W06", monthly: "2026-M02", yearly: "2026"),
            // Week 1 is the week containing Jan 1, so it can open in the previous
            // calendar year and still carry the next year in its key.
            .init(year: 2025, month: 12, day: 29, weekly: "2026-W01", monthly: "2025-M12", yearly: "2025"),
            .init(year: 2026, month: 1, day: 1, weekly: "2026-W01", monthly: "2026-M01", yearly: "2026"),
            .init(year: 2026, month: 12, day: 31, weekly: "2027-W01", monthly: "2026-M12", yearly: "2026"),
            .init(year: 2027, month: 1, day: 1, weekly: "2027-W01", monthly: "2027-M01", yearly: "2027")
        ]
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
