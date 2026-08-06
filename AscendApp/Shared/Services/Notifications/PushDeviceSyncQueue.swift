import Foundation

/// Runs push device synchronizations one at a time.
///
/// Concurrent `registerPushDevice` calls contend on the same Firestore documents server-side, so
/// nothing may overlap. The two ways in differ only in what an already-running sync means for the
/// caller: launch's several triggers are asking the same question, so they `coalesce` onto the run
/// already under way, while a sync whose inputs the climber has just changed carries an answer that
/// run never saw, so it `enqueue`s behind it rather than joining it.
@MainActor
final class PushDeviceSyncQueue {
    private var tail: Task<Void, Never>?
    private var generation = 0

    /// Joins the run already under way, or starts one when the queue is idle.
    func coalesce(_ work: @escaping @Sendable @MainActor () async -> Void) async {
        if let tail {
            await tail.value
            return
        }

        await enqueue(work).value
    }

    /// Queues behind everything already scheduled and hands back without waiting for any of it.
    @discardableResult
    func enqueue(_ work: @escaping @Sendable @MainActor () async -> Void) -> Task<Void, Never> {
        let precedingSync = tail
        generation += 1
        let scheduledGeneration = generation

        let task = Task { @MainActor in
            _ = await precedingSync?.value
            await work()

            if self.generation == scheduledGeneration {
                self.tail = nil
            }
        }

        tail = task
        return task
    }
}
