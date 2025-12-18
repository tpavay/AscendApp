import Foundation

/// Derived progress for a goal - NOT stored, calculated from workouts
struct GoalProgress {
    let current: Int
    let target: Int
    let percent: Double
    let remaining: Int
    let status: GoalStatus
    let weekInterval: DateInterval

    /// Formatted string for the current value with unit
    func formattedCurrent(metric: GoalMetric) -> String {
        let unit = current == 1 ? metric.unitSingular : metric.unit
        return "\(current.formatted()) \(unit)"
    }

    /// Formatted string for progress like "450 / 1,000 steps"
    func formattedProgress(metric: GoalMetric) -> String {
        let unit = target == 1 ? metric.unitSingular : metric.unit
        return "\(current.formatted()) / \(target.formatted()) \(unit)"
    }

    /// Formatted date range like "Dec 15 – Dec 21"
    var formattedDateRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        let start = formatter.string(from: weekInterval.start)

        // End date is exclusive, so subtract 1 second to get the last day
        let endDate = weekInterval.end.addingTimeInterval(-1)
        let end = formatter.string(from: endDate)

        return "\(start) – \(end)"
    }
}
