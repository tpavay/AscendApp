import Testing
@testable import AscendApp

struct HomeStreakCopyTests {
    @Test
    func aSecuredWeekSaysItCountsAndSetsNoDeadline() {
        let copy = HomeStreakCopy(streak: WeeklyStreak(weeks: 3, isCurrentWeekSecured: true))

        #expect(copy.unit == "wks")
        #expect(copy.subtitle == "in a row · this week counts")
        #expect(copy.accessibilityLabel == "Streak: 3 weeks in a row. This week counts.")
        #expect(!copy.subtitle.localizedStandardContains("Sunday"))
    }

    @Test
    func anUnclimbedWeekNamesTheDeadline() {
        let copy = HomeStreakCopy(streak: WeeklyStreak(weeks: 2, isCurrentWeekSecured: false))

        #expect(copy.unit == "wks")
        #expect(copy.subtitle == "Climb by Sunday to keep it")
        #expect(copy.accessibilityLabel == "Streak: 2 weeks in a row. Climb by Sunday to keep it.")
    }

    @Test
    func aOneWeekStreakIsSingular() {
        let copy = HomeStreakCopy(streak: WeeklyStreak(weeks: 1, isCurrentWeekSecured: true))

        #expect(copy.unit == "wk")
        #expect(copy.accessibilityLabel == "Streak: 1 week in a row. This week counts.")
    }

    @Test
    func noStreakDaresTheFirstClimb() {
        let copy = HomeStreakCopy(streak: .none)

        #expect(copy.unit == "wks")
        #expect(copy.subtitle == "Climb this week to start one")
        #expect(copy.accessibilityLabel == "No streak yet. Climb this week to start one.")
    }
}
