import Foundation
import Testing
@testable import AscendApp

/// The one choice a history screen offers: how far back to bring workouts in from. Everything the
/// screen says - the count, the hours, the steps, the button's number - and the identifiers the
/// import is handed all come from the same range, pinned here on fixed dates.
@MainActor
struct HealthHistoryRangeTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver")!
        return calendar
    }

    /// Noon on 9 November 2026 in Denver.
    private static let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!

    private static func workout(daysAgo: Int, steps: Int? = 3_000, minutes: Double = 60) -> HealthWorkoutSnapshot {
        let start = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        return HealthWorkoutSnapshot(
            uuid: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(minutes * 60),
            duration: minutes * 60,
            steps: steps
        )
    }

    private static func choice(_ workouts: [HealthWorkoutSnapshot]) -> HealthHistoryChoice {
        HealthHistoryChoice(history: HealthHistory(workouts: workouts), climbs: [], now: now, calendar: calendar)
    }

    // MARK: - The ranges

    @Test
    func everythingHasNoFloorAndTheOthersCountBackFromNow() {
        let calendar = Self.calendar
        #expect(HealthHistoryRange.everything.earliestStart(now: Self.now, calendar: calendar) == nil)
        #expect(
            HealthHistoryRange.lastYear.earliestStart(now: Self.now, calendar: calendar)
                == calendar.date(from: DateComponents(year: 2025, month: 11, day: 9, hour: 12))
        )
        #expect(
            HealthHistoryRange.last90Days.earliestStart(now: Self.now, calendar: calendar)
                == calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 12))
        )
        let picked = calendar.date(from: DateComponents(year: 2024, month: 3, day: 3, hour: 17, minute: 40))!
        #expect(
            HealthHistoryRange.since(picked).earliestStart(now: Self.now, calendar: calendar)
                == calendar.date(from: DateComponents(year: 2024, month: 3, day: 3)),
            "a picked day starts at its midnight"
        )
    }

    @Test
    func eachRangeHasItsOwnStableAnalyticsName() {
        #expect(HealthHistoryRange.everything.analyticsID == "everything")
        #expect(HealthHistoryRange.lastYear.analyticsID == "last_year")
        #expect(HealthHistoryRange.last90Days.analyticsID == "last_90_days")
        #expect(HealthHistoryRange.since(Self.now).analyticsID == "since_date")
    }

    // MARK: - What follows the range

    @Test
    func theCountTheHoursTheStepsAndTheIdentifiersAllFollowTheRange() {
        let recent = Self.workout(daysAgo: 10, steps: 2_000)
        let thisYear = Self.workout(daysAgo: 200, steps: 4_000)
        let old = Self.workout(daysAgo: 800, steps: 8_000)
        let history = HealthHistory(workouts: [old, recent, thisYear])

        let everything = history.summary(in: .everything, now: Self.now, calendar: Self.calendar)
        #expect(everything.workoutCount == 3)
        #expect(everything.knownSteps == 14_000)
        #expect(everything.totalDurationText == "3 hours")
        #expect(Set(everything.workoutIDs) == [old, recent, thisYear].reduce(into: Set<String>()) { $0.insert($1.uuid.uuidString) })

        let lastYear = history.summary(in: .lastYear, now: Self.now, calendar: Self.calendar)
        #expect(lastYear.workoutCount == 2)
        #expect(lastYear.knownSteps == 6_000)
        #expect(lastYear.totalDurationText == "2 hours")
        #expect(Set(lastYear.workoutIDs) == [recent.uuid.uuidString, thisYear.uuid.uuidString])

        let last90 = history.summary(in: .last90Days, now: Self.now, calendar: Self.calendar)
        #expect(last90.workoutIDs == [recent.uuid.uuidString])
        #expect(last90.knownSteps == 2_000)
        #expect(last90.totalDurationText == "1 hour")

        let since = history.summary(in: .since(thisYear.startDate), now: Self.now, calendar: Self.calendar)
        #expect(since.workoutCount == 2, "the picked day's own workout is inside")
    }

    @Test
    func aWorkoutThatCannotBeAClimbIsNotPartOfAnyRange() {
        let history = HealthHistory(workouts: [
            Self.workout(daysAgo: 5),
            Self.workout(daysAgo: 6, minutes: 0.005),
            Self.workout(daysAgo: 7, minutes: 25 * 60)
        ])

        #expect(history.workouts.count == 1)
        #expect(history.count(in: .everything, now: Self.now, calendar: Self.calendar) == 1)
    }

    // MARK: - The choice

    @Test
    func theDefaultIsEverythingNamedByTheMonthOfTheOldestWorkout() {
        let choice = Self.choice([Self.workout(daysAgo: 10), Self.workout(daysAgo: 800)])

        #expect(choice.range == .everything)
        #expect(choice.rangeLabel == "Everything since August 2024")
        #expect(choice.primaryTitle == "Add 2 to my history")
        #expect(choice.summary.workoutCount == 2)
    }

    @Test
    func pickingARangeChangesTheLabelTheButtonAndTheSummaryTogether() {
        let choice = Self.choice([
            Self.workout(daysAgo: 10, steps: 2_000),
            Self.workout(daysAgo: 200, steps: 4_000),
            Self.workout(daysAgo: 800, steps: 8_000)
        ])

        choice.select(.lastYear)
        #expect(choice.rangeLabel == "Last year")
        #expect(choice.primaryTitle == "Add 2 to my history")
        #expect(choice.summary.knownSteps == 6_000)

        choice.select(.last90Days)
        #expect(choice.rangeLabel == "Last 90 days")
        #expect(choice.primaryTitle == "Add 1 to my history")

        let day = Self.calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        choice.select(.since(day))
        #expect(choice.rangeLabel == "Since Apr 1, 2026")
        #expect(choice.primaryTitle == "Add 2 to my history")

        choice.select(.everything)
        #expect(choice.primaryTitle == "Add 3 to my history")
        #expect(choice.summary.knownSteps == 14_000)
    }

    @Test
    func theComparisonFollowsTheRangesSteps() {
        // Three workouts of 30,000 steps over 20 hours each: two Everests in all, one in the last year.
        let choice = Self.choice([
            Self.workout(daysAgo: 10, steps: 30_000, minutes: 1_200),
            Self.workout(daysAgo: 200, steps: 30_000, minutes: 1_200),
            Self.workout(daysAgo: 800, steps: 40_000, minutes: 1_200)
        ])
        #expect(choice.comparison?.timesOver == 2)

        choice.select(.lastYear)
        #expect(choice.comparison?.timesOver == 1)

        choice.select(.last90Days)
        #expect(choice.comparison == nil, "30,000 steps is under one Everest and no climb was offered to compare with")
    }

    @Test
    func theDateRowOnlyOffersDaysThatLeaveSomethingToBringIn() throws {
        let oldest = Self.workout(daysAgo: 800)
        let newest = Self.workout(daysAgo: 10)
        let choice = Self.choice([newest, oldest])

        let days = try #require(choice.pickableDays)
        #expect(days.lowerBound == Self.calendar.startOfDay(for: oldest.startDate))
        #expect(days.upperBound == newest.startDate)
        choice.select(.since(days.upperBound))
        #expect(choice.summary.workoutCount == 1, "the last day it offers still holds a workout")
    }

    @Test
    func aPresetWithNothingInsideItCountsAsNone() {
        let choice = Self.choice([Self.workout(daysAgo: 800)])

        #expect(choice.count(in: .lastYear) == 0)
        #expect(choice.count(in: .last90Days) == 0)
        #expect(choice.count(in: .everything) == 1)
        #expect(HealthHistoryRangeSheet.detail(count: 0) == "None")
        #expect(HealthHistoryRangeSheet.detail(count: 1) == "1 workout")
        #expect(HealthHistoryRangeSheet.detail(count: 312) == "312 workouts")
    }

    @Test
    func thePickerListsEverythingLastYearAndLastNinetyDaysAboveTheDate() {
        #expect(HealthHistoryChoice.presets == [.everything, .lastYear, .last90Days])
        #expect(HealthHistoryChoice.presets.map(HealthHistoryRangeSheet.title(for:)) == ["Everything", "Last year", "Last 90 days"])
    }
}
