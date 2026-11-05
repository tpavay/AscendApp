import Foundation
import Testing
@testable import AscendApp

/// The wording and moments of the local reminders, from facts alone. The calendar is fixed to
/// Monday weeks in UTC so every date below is exact.
struct LocalReminderPlanTests {
    private let calendar = WeekConfiguration.calendar(timeZone: TimeZone(identifier: "UTC")!)

    /// Monday 2026-11-02 is the week these tests live in.
    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    private func weekly(target: Int?, climbs: [Date] = [], minutes: Int? = nil, now: Date) -> [LocalReminderRequest] {
        LocalReminderPlan.weeklyTarget(
            targetDays: target,
            climbDates: climbs,
            usualClimbMinutes: minutes,
            now: now,
            calendar: calendar
        )
    }

    @Test
    func noTargetSchedulesNothing() {
        #expect(weekly(target: nil, now: date(2)).isEmpty)
        #expect(weekly(target: 0, now: date(2)).isEmpty)
        #expect(weekly(target: 8, now: date(2)).isEmpty)
    }

    /// Three days owed on Monday: the last day the week can still be saved is Friday, when exactly
    /// three days (Fri, Sat, Sun) remain.
    @Test
    func theNudgeLandsOnTheLastDayTheTargetCanStillBeMet() throws {
        let requests = weekly(target: 3, now: date(2))

        let thisWeek = try #require(requests.first { $0.identifier == LocalReminderPlan.thisWeekIdentifier })
        #expect(thisWeek.fireDate == date(6, hour: 18))
        #expect(thisWeek.title == "Your week is still open")
        #expect(thisWeek.body == "Your target is 3 days a week. 20 minutes gets you started.")

        let nextWeek = try #require(requests.first { $0.identifier == LocalReminderPlan.nextWeekIdentifier })
        #expect(nextWeek.fireDate == date(13, hour: 18))
    }

    @Test
    func aClimberOneDayShortGetsTheOneClimbNudgeWithTheirOwnCount() throws {
        let climbs = [date(2), date(3)]
        let requests = weekly(target: 3, climbs: climbs, minutes: 41, now: date(4))

        let thisWeek = try #require(requests.first { $0.identifier == LocalReminderPlan.thisWeekIdentifier })
        #expect(thisWeek.title == "One climb from your target")
        #expect(thisWeek.body == "2 of 3 days done this week. 41 minutes gets it done.")
        // One day owed, so the last day to save the week is Sunday.
        #expect(thisWeek.fireDate == date(8, hour: 18))
    }

    @Test
    func twoClimbsOnOneDayCountOnce() throws {
        let climbs = [date(2, hour: 7), date(2, hour: 19)]
        let requests = weekly(target: 2, climbs: climbs, now: date(3))

        let thisWeek = try #require(requests.first { $0.identifier == LocalReminderPlan.thisWeekIdentifier })
        #expect(thisWeek.title == "One climb from your target")
        #expect(thisWeek.body.hasPrefix("1 of 2 days done this week."))
    }

    @Test
    func aMetTargetSchedulesNothingForThisWeekButStillWatchesNext() {
        let climbs = [date(2), date(3), date(4)]
        let requests = weekly(target: 3, climbs: climbs, now: date(5))

        #expect(requests.map(\.identifier) == [LocalReminderPlan.nextWeekIdentifier])
    }

    @Test
    func aWeekWhoseLastChancePassedGetsNoNudge() {
        // Target 7 owes every day, so the only moment was Monday 18:00 - already behind on Tuesday.
        let requests = weekly(target: 7, now: date(3))
        #expect(requests.map(\.identifier) == [LocalReminderPlan.nextWeekIdentifier])
    }

    @Test
    func aNudgeNeverFiresInThePast() {
        // Friday 19:00, target 3, nothing climbed: Friday 18:00 is gone.
        let requests = weekly(target: 3, now: date(6, hour: 19))
        #expect(requests.allSatisfy { $0.fireDate > date(6, hour: 19) })
        #expect(requests.map(\.identifier) == [LocalReminderPlan.nextWeekIdentifier])
    }

    @Test
    func aSundayClimbBelongsToTheMondayWeekItEnds() throws {
        // Monday 2 Nov through Sunday 8 Nov is one week; a climb on Sunday 1 Nov is last week's.
        let lastSunday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
        let requests = weekly(target: 1, climbs: [lastSunday], now: date(3))

        let thisWeek = requests.first { $0.identifier == LocalReminderPlan.thisWeekIdentifier }
        #expect(thisWeek != nil, "last week's climb must not meet this week's target")
    }

    @Test
    func theQuotedMinutesFallBackWhenTheUsualClimbIsNotPlausible() {
        #expect(LocalReminderPlan.quotedMinutes(nil) == 20)
        #expect(LocalReminderPlan.quotedMinutes(0) == 20)
        #expect(LocalReminderPlan.quotedMinutes(500) == 20)
        #expect(LocalReminderPlan.quotedMinutes(41) == 41)
    }

    // MARK: - Trial

    @Test
    func noStartedTrialMeansNoReminder() {
        #expect(LocalReminderPlan.trialEnding(trialStartedAt: nil, now: date(2), calendar: calendar) == nil)
    }

    @Test
    func theTrialReminderFiresOnDayFiveOfTheSeven() throws {
        let started = date(2, hour: 9)
        let request = try #require(LocalReminderPlan.trialEnding(trialStartedAt: started, now: date(2, hour: 10), calendar: calendar))

        #expect(request.fireDate == date(7, hour: 9))
        #expect(request.identifier == LocalReminderPlan.trialEndingIdentifier)
        #expect(request.title == "Your free week ends in 2 days")
        #expect(request.body == "No surprise charges. Cancel any time in Settings.")
    }

    @Test
    func aTrialPastItsDayFiveGetsNothing() {
        let started = date(2, hour: 9)
        #expect(LocalReminderPlan.trialEnding(trialStartedAt: started, now: date(8), calendar: calendar) == nil)
    }

    // MARK: - Copy rules

    @Test
    func noReminderUsesAnEmDashOrTheBannedWords() {
        var lines: [String] = []
        for target in 1...7 {
            for done in 0..<target {
                lines.append(LocalReminderPlan.weeklyTitle(daysOwed: target - done, daysDone: done))
                lines.append(LocalReminderPlan.weeklyBody(targetDays: target, daysDone: done, minutes: 20))
            }
        }
        lines.append("Your free week ends in 2 days")
        lines.append("No surprise charges. Cancel any time in Settings.")

        for line in lines {
            let lowered = line.lowercased()
            #expect(!line.contains("\u{2014}"), "\(line)")
            for word in ["race", "live", "field"] {
                #expect(!lowered.contains(word), "\(line)")
            }
        }
    }
}
