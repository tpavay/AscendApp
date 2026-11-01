import Foundation

struct LeaderboardWorkoutSnapshot: Equatable, Sendable, Identifiable {
    let id: UUID
    let date: Date
    let duration: TimeInterval
    let steps: Int
    let floors: Int
    /// Whether the climb is on the boards at all. A climb the pace check kept off them adds
    /// nothing to the optimistic overlay, so a climber is never shown a total the server will not
    /// rank them on.
    let countsTowardLeaderboards: Bool

    init(
        id: UUID,
        date: Date,
        duration: TimeInterval,
        steps: Int,
        floors: Int,
        countsTowardLeaderboards: Bool = true
    ) {
        self.id = id
        self.date = date
        self.duration = duration
        self.steps = steps
        self.floors = floors
        self.countsTowardLeaderboards = countsTowardLeaderboards
    }

    init(workout: Workout) {
        self.init(
            id: workout.id,
            date: workout.date,
            duration: workout.duration,
            steps: workout.steps,
            floors: workout.floors,
            countsTowardLeaderboards: workout.leaderboardStatus == .eligible
        )
    }

    var aggregate: LeaderboardAggregate {
        guard countsTowardLeaderboards else { return .zero }
        return LeaderboardAggregate(
            totalSteps: steps,
            totalFloors: floors,
            totalWorkouts: 1,
            totalDuration: duration
        )
    }
}
