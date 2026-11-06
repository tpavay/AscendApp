import Foundation
import Testing
@testable import AscendApp

struct DailyRoutineRecommendationPolicyTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(day: Int, hour: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }

    @Test("Today's routine is one of the featured built-ins, with its length in minutes")
    func thePickIsAFeaturedRoutineWithItsLength() throws {
        let pick = try #require(DailyRoutineRecommendationPolicy.recommendation(on: date(day: 10, hour: 12), calendar: utc))
        let definition = try #require(BuiltInRoutines.definitions.first { $0.id == pick.templateId })

        #expect(definition.isFeatured)
        #expect(pick.name == definition.name)
        #expect(pick.durationMinutes == Int((definition.intervals.reduce(0) { $0 + $1.duration } / 60).rounded()))
    }

    @Test("The pick holds all day and rolls over at the daily climb's hour")
    func thePickRollsOverAtTheSameHourAsTheDailyClimb() throws {
        let hour = DailyClimbRecommendationPolicy.rolloverHour
        let beforeRollover = try #require(DailyRoutineRecommendationPolicy.recommendation(on: date(day: 10, hour: hour - 1), calendar: utc))
        let yesterdayNoon = try #require(DailyRoutineRecommendationPolicy.recommendation(on: date(day: 9, hour: 12), calendar: utc))
        let afterRollover = try #require(DailyRoutineRecommendationPolicy.recommendation(on: date(day: 10, hour: hour), calendar: utc))
        let laterThatDay = try #require(DailyRoutineRecommendationPolicy.recommendation(on: date(day: 10, hour: 22), calendar: utc))

        #expect(beforeRollover == yesterdayNoon)
        #expect(afterRollover == laterThatDay)
    }

    @Test("Consecutive days walk the featured routines, so every one gets a day")
    func consecutiveDaysCoverEveryFeaturedRoutine() {
        let featured = Set(BuiltInRoutines.definitions.filter(\.isFeatured).map(\.id))
        let seen = Set((0..<featured.count).compactMap { offset in
            DailyRoutineRecommendationPolicy.recommendation(on: date(day: 10 + offset, hour: 12), calendar: utc)?.templateId
        })

        #expect(seen == featured)
    }

    @Test("Without a featured routine there is no pick")
    func noFeaturedRoutineMeansNoPick() {
        #expect(DailyRoutineRecommendationPolicy.recommendation(from: []) == nil)
    }

    @Test("A pick words its row, and a missing one leaves the row to say what it is for")
    func picksWordTheirRows() {
        let picks = HomeStartPicks(
            landmark: nil,
            routine: DailyRoutineRecommendationPolicy.Pick(templateId: "pyramid_climb", name: "Pyramid Climb", durationMinutes: 20)
        )

        #expect(picks.line(for: .routines) == "Today: Pyramid Climb · 20 min")
        #expect(picks.line(for: .browseClimbs) == nil)
        #expect(picks.line(for: .justClimb) == nil)
        #expect(HomeStartAction.browseClimbs.offersSeeAll)
        #expect(HomeStartAction.routines.offersSeeAll)
        #expect(!HomeStartAction.justClimb.offersSeeAll)
    }
}
