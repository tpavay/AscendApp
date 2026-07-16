import Foundation

struct LeaderboardAggregate: Equatable, Sendable {
    static let zero = LeaderboardAggregate()

    var totalSteps: Int = 0
    var totalFloors: Int = 0
    var totalWorkouts: Int = 0
    var totalDuration: TimeInterval = 0

    var stepsPerMinute: Double {
        let minutes = totalDuration / 60
        guard minutes > 0 else { return 0 }
        return Double(totalSteps) / minutes
    }

    var floorsPerMinute: Double {
        let minutes = totalDuration / 60
        guard minutes > 0 else { return 0 }
        return Double(totalFloors) / minutes
    }

    static func + (lhs: LeaderboardAggregate, rhs: LeaderboardAggregate) -> LeaderboardAggregate {
        LeaderboardAggregate(
            totalSteps: lhs.totalSteps + rhs.totalSteps,
            totalFloors: lhs.totalFloors + rhs.totalFloors,
            totalWorkouts: lhs.totalWorkouts + rhs.totalWorkouts,
            totalDuration: lhs.totalDuration + rhs.totalDuration
        )
    }

    static func - (lhs: LeaderboardAggregate, rhs: LeaderboardAggregate) -> LeaderboardAggregate {
        LeaderboardAggregate(
            totalSteps: lhs.totalSteps - rhs.totalSteps,
            totalFloors: lhs.totalFloors - rhs.totalFloors,
            totalWorkouts: lhs.totalWorkouts - rhs.totalWorkouts,
            totalDuration: lhs.totalDuration - rhs.totalDuration
        )
    }
}
