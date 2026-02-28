import Foundation

/// Pure, stateless service for calculating goal progress
/// Safe to call from anywhere - does NOT use Calendar.current
struct GoalProgressService {

    /// Build a calendar from the goal's locked settings
    /// - Parameter goal: The goal with locked timezone and firstWeekday
    /// - Returns: A calendar configured with the goal's settings
    static func makeCalendar(for goal: Goal) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: goal.timeZoneId) ?? .current
        calendar.firstWeekday = goal.firstWeekday
        return calendar
    }

    /// Get the current week interval using the goal's locked calendar
    /// - Parameters:
    ///   - goal: The goal with locked settings
    ///   - now: The current date (defaults to Date())
    /// - Returns: The date interval for the current week
    static func weekInterval(for goal: Goal, at now: Date = Date()) -> DateInterval {
        let calendar = makeCalendar(for: goal)
        return calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, duration: 7 * 24 * 60 * 60)
    }

    /// Calculate progress for a goal from workouts
    /// - Parameters:
    ///   - goal: The goal to calculate progress for
    ///   - workouts: All workouts to filter and aggregate
    /// - Returns: The calculated progress
    static func calculateProgress(
        for goal: Goal,
        from workouts: [Workout],
        at now: Date = Date()
    ) -> GoalProgress {
        let interval = weekInterval(for: goal, at: now)

        // Filter workouts to current week
        let weekWorkouts = workouts.filter { workout in
            interval.contains(workout.date)
        }

        // Calculate current value based on metric
        let current: Int
        switch goal.metric {
        case .steps:
            current = weekWorkouts.reduce(0) { $0 + $1.steps }
        case .floors:
            current = weekWorkouts.reduce(0) { $0 + $1.floors }
        case .duration:
            // duration is stored in seconds, convert to minutes
            let totalSeconds = weekWorkouts.reduce(0.0) { $0 + $1.duration }
            current = Int(totalSeconds / 60)
        case .workouts:
            current = weekWorkouts.count
        }

        // Calculate percentage (can exceed 100%)
        let percent = goal.target > 0 ? Double(current) / Double(goal.target) : 0

        // Calculate remaining (minimum 0)
        let remaining = max(0, goal.target - current)

        // Determine status
        let status: GoalStatus
        if current >= goal.target {
            status = .complete
        } else {
            // Could add day-of-week logic for "behind" in the future
            status = .onTrack
        }

        return GoalProgress(
            current: current,
            target: goal.target,
            percent: percent,
            remaining: remaining,
            status: status,
            weekInterval: interval
        )
    }

    /// Calculate progress for the previous week
    /// - Parameters:
    ///   - goal: The goal to calculate progress for
    ///   - workouts: All workouts to filter and aggregate
    /// - Returns: The calculated progress for last week, or nil if no data
    static func calculateLastWeekProgress(
        for goal: Goal,
        from workouts: [Workout]
    ) -> GoalProgress? {
        let currentInterval = weekInterval(for: goal)

        // Calculate last week's interval by shifting back 7 days
        let lastWeekStart = currentInterval.start.addingTimeInterval(-7 * 24 * 60 * 60)
        let lastWeekEnd = currentInterval.start
        let lastWeekInterval = DateInterval(start: lastWeekStart, end: lastWeekEnd)

        // Filter workouts to last week
        let weekWorkouts = workouts.filter { workout in
            lastWeekInterval.contains(workout.date)
        }

        // If no workouts last week, return nil
        guard !weekWorkouts.isEmpty else { return nil }

        // Calculate current value based on metric
        let current: Int
        switch goal.metric {
        case .steps:
            current = weekWorkouts.reduce(0) { $0 + $1.steps }
        case .floors:
            current = weekWorkouts.reduce(0) { $0 + $1.floors }
        case .duration:
            // duration is stored in seconds, convert to minutes
            let totalSeconds = weekWorkouts.reduce(0.0) { $0 + $1.duration }
            current = Int(totalSeconds / 60)
        case .workouts:
            current = weekWorkouts.count
        }

        // Calculate percentage (can exceed 100%)
        let percent = goal.target > 0 ? Double(current) / Double(goal.target) : 0

        // Calculate remaining (minimum 0)
        let remaining = max(0, goal.target - current)

        // Determine status
        let status: GoalStatus = current >= goal.target ? .complete : .onTrack

        return GoalProgress(
            current: current,
            target: goal.target,
            percent: percent,
            remaining: remaining,
            status: status,
            weekInterval: lastWeekInterval
        )
    }
}
