import Foundation

struct LeaderboardWorkoutSnapshot: Equatable, Sendable, Identifiable {
    let id: UUID
    let date: Date
    let duration: TimeInterval
    let steps: Int
    let floors: Int

    init(id: UUID, date: Date, duration: TimeInterval, steps: Int, floors: Int) {
        self.id = id
        self.date = date
        self.duration = duration
        self.steps = steps
        self.floors = floors
    }

    init(workout: Workout) {
        self.init(
            id: workout.id,
            date: workout.date,
            duration: workout.duration,
            steps: workout.steps,
            floors: workout.floors
        )
    }

    var aggregate: LeaderboardAggregate {
        LeaderboardAggregate(
            totalSteps: steps,
            totalFloors: floors,
            totalWorkouts: 1,
            totalDuration: duration
        )
    }
}
