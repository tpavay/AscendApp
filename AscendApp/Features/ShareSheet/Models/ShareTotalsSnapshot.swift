import Foundation

/// The climber's totals for the current week, month or year, resolved once for the Totals stickers.
///
/// Pure value type: the stickers read it and nothing else, so a sticker never reaches into the
/// store. Weeks start on Monday, like every week in the app.
struct ShareTotalsSnapshot: Equatable, Sendable {
    struct Standing: Equatable, Sendable {
        let position: Int
        let field: Int

        init?(position: Int?, field: Int?) {
            guard let position, let field, position > 0, field > 0 else { return nil }
            self.position = min(position, field)
            self.field = field
        }

        var positionText: String { "#\(groupedPosition)" }
        var fieldText: String { field.formatted(.number.grouping(.automatic)) }

        /// `TOP 3%`, never below 1.
        var topPercent: Int {
            max(1, Int((Double(position) / Double(field) * 100).rounded()))
        }

        /// The share of the field behind this finish, 0 to 1, for the bell curve marker.
        var beatFraction: Double {
            Double(field - position) / Double(field)
        }
    }

    let period: SharePeriod
    /// `THIS WEEK`, `THIS MONTH`, `THIS YEAR`.
    let periodCaption: String
    let steps: Int
    let durationSeconds: Int
    /// Steps divided by 16, summed over the period's climbs.
    let floors: Int
    let climbs: Int

    /// The current month's grid: its name (`OCTOBER`), how many empty cells precede day 1 in a
    /// Monday-first week, the number of days, and which days had a climb.
    let calendarMonthName: String
    let calendarLeadingBlanks: Int
    let calendarDayCount: Int
    let calendarClimbDays: Set<Int>
    /// How many climbs the month holds, for the calendar's `N CLIMBS`.
    let calendarClimbCount: Int

    /// Steps for each of the last six weeks, oldest first; the last is the current week.
    let weeklySteps: [Int]
    /// Total steps over total minutes across the last 30 days, or nil with no climbs.
    let averagePace30Days: Double?
    /// Monday to Sunday: whether the climber climbed that day this week.
    let weekDays: [Bool]

    /// The climber's steps standing for each period, or nil when it could not be read.
    let weekStanding: Standing?
    let monthStanding: Standing?
    let yearStanding: Standing?

    var stepsText: String { steps.formatted(.number.grouping(.automatic)) }
    var floorsText: String { floors.formatted(.number.grouping(.automatic)) }
    var climbsText: String { "\(climbs)" }
    var durationText: String { ShareSheetFormat.clock(durationSeconds) }

    var hasClimbs: Bool { climbs > 0 }

    /// Standing for the period this snapshot summarises.
    var standing: Standing? {
        switch period {
        case .week: return weekStanding
        case .month: return monthStanding
        case .year: return yearStanding
        }
    }
}
