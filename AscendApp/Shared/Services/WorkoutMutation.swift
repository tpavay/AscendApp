import Foundation

struct WorkoutMutation: Equatable, Sendable {
    struct Update: Equatable, Sendable {
        let before: LeaderboardWorkoutSnapshot
        let after: LeaderboardWorkoutSnapshot
    }

    var created: [LeaderboardWorkoutSnapshot]
    var updated: [Update]
    var deleted: [LeaderboardWorkoutSnapshot]
    var requiresFullRebuild: Bool

    init(
        created: [LeaderboardWorkoutSnapshot] = [],
        updated: [Update] = [],
        deleted: [LeaderboardWorkoutSnapshot] = [],
        requiresFullRebuild: Bool = false
    ) {
        self.created = created
        self.updated = updated
        self.deleted = deleted
        self.requiresFullRebuild = requiresFullRebuild
    }

    static func created(_ workouts: [LeaderboardWorkoutSnapshot]) -> WorkoutMutation {
        WorkoutMutation(created: workouts)
    }

    static func imported(_ workouts: [LeaderboardWorkoutSnapshot]) -> WorkoutMutation {
        WorkoutMutation(created: workouts)
    }

    static func deleted(_ workouts: [LeaderboardWorkoutSnapshot]) -> WorkoutMutation {
        WorkoutMutation(deleted: workouts)
    }

    static func updated(before: LeaderboardWorkoutSnapshot, after: LeaderboardWorkoutSnapshot) -> WorkoutMutation {
        WorkoutMutation(updated: [Update(before: before, after: after)])
    }

    static let rebuildAll = WorkoutMutation(requiresFullRebuild: true)
}
