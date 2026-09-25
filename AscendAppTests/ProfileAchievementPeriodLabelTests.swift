import Foundation
import Testing
@testable import AscendApp

/// A finalized finish names the UTC window it was ranked over, whatever zone the climber
/// reads it from. Every boundary is UTC midnight, which is still the previous evening
/// anywhere west of UTC, so a label rendered in the viewer's zone names the wrong month,
/// the wrong year, and a week that starts a day early.
///
/// CI runs in UTC, where the device zone and the window's zone agree and this defect is
/// invisible; `LeaderboardTimeFrameTests` pins the styles to UTC so CI still catches a
/// regression. Run this suite with `TEST_RUNNER_TZ=America/Chicago` to watch it on a
/// US climber's device.
struct ProfileAchievementPeriodLabelTests {
    @Test
    func aMonthlyTitleNamesTheMonthItWasWon() {
        let record = record(type: .monthlyTop1, period: .monthly, containing: utcDate(2026, 8, 15))

        #expect(record.periodLabel == "August 2026")
    }

    @Test
    func aYearlyTitleNamesTheYearItWasWon() {
        let record = record(type: .yearlyTop10, period: .yearly, containing: utcDate(2026, 6, 1))

        #expect(record.periodLabel == "2026")
    }

    /// Monday to the inclusive Sunday: `periodEndAt` is the next Monday, exclusive.
    @Test
    func aWeeklyFinishNamesMondayThroughSunday() {
        let record = record(type: .weeklyTop100, period: .weekly, containing: utcDate(2026, 8, 1))

        #expect(record.periodLabel == "Jul 27 - Aug 2, 2026")
    }

    @Test
    func aWeekThatCrossesNewYearIsDatedByTheYearItEnds() {
        let record = record(type: .weeklyTop1, period: .weekly, containing: utcDate(2026, 12, 30))

        #expect(record.periodLabel == "Dec 28 - Jan 3, 2027")
    }

    @Test
    func aRecordWithoutAWindowHasNoPeriodLabel() {
        let record = ProfileAchievementRecord(
            id: "first-ascent",
            type: .firstAscent,
            scope: .climb,
            metric: .completionTime,
            climbId: "empire-state",
            periodKey: nil,
            periodStartAt: nil,
            periodEndAt: nil,
            earnedAt: utcDate(2026, 8, 1),
            rank: 1,
            value: 900,
            valueUnit: "seconds"
        )

        #expect(record.periodLabel == nil)
    }

    /// Built from the same period derivation the finalizer mirrors, so the record carries
    /// exactly the key and UTC boundaries a finalized achievement document does.
    private func record(
        type: ProfileAchievementType,
        period timeFrame: LeaderboardTimeFrame,
        containing instant: Date
    ) -> ProfileAchievementRecord {
        let period = timeFrame.currentPeriod(referenceDate: instant)
        return ProfileAchievementRecord(
            id: "global_steps_\(timeFrame.rawValue)_\(period.key)",
            type: type,
            scope: .global,
            metric: .steps,
            climbId: nil,
            periodKey: period.key,
            periodStartAt: period.startAt,
            periodEndAt: period.endAt,
            earnedAt: period.endAt ?? instant,
            rank: 1,
            value: 42_000,
            valueUnit: "steps"
        )
    }

    private func utcDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.calendar = WeekConfiguration.calendar(timeZone: LeaderboardTimeFrame.canonicalTimeZone)
        components.timeZone = LeaderboardTimeFrame.canonicalTimeZone
        components.year = year
        components.month = month
        components.day = day
        return components.date!
    }
}
