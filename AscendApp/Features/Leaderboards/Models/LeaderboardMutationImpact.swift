import Foundation

enum LeaderboardMutationImpact: Equatable, Sendable {
    struct Change: Equatable, Sendable {
        let before: LeaderboardWorkoutSnapshot?
        let after: LeaderboardWorkoutSnapshot?
    }

    case none
    case incremental([Change])
    case rebuildAll

    static func classify(_ mutation: WorkoutMutation) -> LeaderboardMutationImpact {
        if mutation.requiresFullRebuild {
            return .rebuildAll
        }

        var changes: [Change] = mutation.created.map { Change(before: nil, after: $0) }
        changes.append(contentsOf: mutation.deleted.map { Change(before: $0, after: nil) })

        for update in mutation.updated where update.before != update.after {
            guard relevantFieldsChanged(before: update.before, after: update.after) else { continue }
            changes.append(Change(before: update.before, after: update.after))
        }

        if changes.isEmpty {
            return .none
        }

        return .incremental(changes)
    }

    private static func relevantFieldsChanged(
        before: LeaderboardWorkoutSnapshot,
        after: LeaderboardWorkoutSnapshot
    ) -> Bool {
        before.date != after.date ||
        before.duration != after.duration ||
        before.steps != after.steps ||
        before.floors != after.floors
    }
}
