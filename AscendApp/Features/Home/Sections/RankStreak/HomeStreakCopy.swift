import Foundation

/// What the Home streak tile says about a `WeeklyStreak`.
///
/// The week ends Sunday app-wide (Monday start), so the deadline is always the same day;
/// it is only worth saying while this week still has no climb. Once it has one the streak
/// is safe until next Monday, and the tile says so instead of warning.
struct HomeStreakCopy: Equatable {
    let unit: String
    let subtitle: String
    let accessibilityLabel: String

    init(streak: WeeklyStreak) {
        let weeks = streak.weeks
        unit = weeks == 1 ? "wk" : "wks"

        guard weeks > 0 else {
            subtitle = "Climb this week to start one"
            accessibilityLabel = "No streak yet. Climb this week to start one."
            return
        }

        let spokenWeeks = "\(weeks) \(weeks == 1 ? "week" : "weeks") in a row"
        if streak.isCurrentWeekSecured {
            subtitle = "in a row · this week counts"
            accessibilityLabel = "Streak: \(spokenWeeks). This week counts."
        } else {
            subtitle = "Climb by Sunday to keep it"
            accessibilityLabel = "Streak: \(spokenWeeks). Climb by Sunday to keep it."
        }
    }
}
