import Foundation

struct HomeWeeklyStats: Equatable, Sendable {
    let climbs: Int
    let steps: Int
    let durationText: String

    static let zero = HomeWeeklyStats(climbs: 0, steps: 0, durationText: "0 min")

    static func make(from workouts: [Workout]) -> HomeWeeklyStats {
        var climbs = 0
        var steps = 0
        var duration: TimeInterval = 0

        for workout in workouts {
            climbs += 1
            steps += workout.steps
            duration += workout.duration
        }

        return HomeWeeklyStats(
            climbs: climbs,
            steps: steps,
            durationText: format(duration: duration)
        )
    }

    private static func format(duration: TimeInterval) -> String {
        let totalMinutes = Int(duration / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }

        return "\(minutes) min"
    }
}
