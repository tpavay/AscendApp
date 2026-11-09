import Foundation

/// Where an imported workout's steps come from. The whole rule, in one place:
///
/// 1. The workout carries steps of its own: those are the climb's steps.
/// 2. It carries none, or zero: the steps Health counted between the workout's start and its end.
/// 3. Health counted none there either: the climb arrives without steps and asks for them.
///
/// Either number is the climb's number. Nothing downstream can tell the two apart, and nothing a
/// climber sees says which it was: a climber who thinks the steps are off opens the climb and
/// edits it, the same as a climb they typed.
///
/// Every read of a stair workout goes through here before the workout is filed, summarised or
/// imported - the pass, the history backfill, the fresh read at import time, and the history
/// screens' totals - so the number a screen promises is the number that lands.
@MainActor
enum HealthWorkoutStepRule {
    /// How many window reads run at once. Each is one small statistics query, so a history of a
    /// few hundred workouts resolves in a handful of rounds instead of one query at a time.
    static let concurrentWindowReads = 12

    static func needsWindowRead(_ snapshot: HealthWorkoutSnapshot) -> Bool {
        (snapshot.steps ?? 0) <= 0 && snapshot.endDate > snapshot.startDate
    }

    static func resolve(
        _ snapshot: HealthWorkoutSnapshot,
        using reader: any HealthWorkoutReading
    ) async -> HealthWorkoutSnapshot {
        guard needsWindowRead(snapshot) else { return snapshot }
        // A read that fails leaves the steps unknown, which is what they were. The import reads
        // the workout again at the moment it becomes a climb, so the window gets a second look.
        let counted = try? await reader.stepCount(from: snapshot.startDate, to: snapshot.endDate)
        guard let counted, counted > 0 else { return snapshot.withSteps(nil) }
        return snapshot.withSteps(counted)
    }

    /// Resolves many workouts, in order, with a bounded number of window reads in flight.
    static func resolve(
        _ snapshots: [HealthWorkoutSnapshot],
        using reader: any HealthWorkoutReading
    ) async -> [HealthWorkoutSnapshot] {
        var resolved = snapshots
        let pending = snapshots.indices.filter { needsWindowRead(snapshots[$0]) }

        var cursor = pending.startIndex
        while cursor < pending.endIndex, !Task.isCancelled {
            let batch = pending[cursor..<min(cursor + concurrentWindowReads, pending.endIndex)]
            cursor = batch.endIndex

            let settled = await withTaskGroup(
                of: (Int, HealthWorkoutSnapshot).self,
                returning: [(Int, HealthWorkoutSnapshot)].self
            ) { group in
                for index in batch {
                    let snapshot = snapshots[index]
                    group.addTask {
                        (index, await resolve(snapshot, using: reader))
                    }
                }
                var settled: [(Int, HealthWorkoutSnapshot)] = []
                for await result in group {
                    settled.append(result)
                }
                return settled
            }
            for (index, snapshot) in settled {
                resolved[index] = snapshot
            }
        }
        return resolved
    }
}
