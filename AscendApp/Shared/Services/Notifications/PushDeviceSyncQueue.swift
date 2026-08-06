import Foundation

/// Runs push device synchronizations one at a time.
///
/// Concurrent `registerPushDevice` calls contend on the same Firestore documents server-side, so
/// nothing may overlap. What separates the two ways in is whether a run already scheduled can
/// answer for the caller. A refresh takes its own reading of iOS authorization, so two of them ask
/// the same question and the second may `coalesce` onto the first. A mutation's sync carries the
/// status captured when the climber answered, so it can never stand in for a refresh - and a
/// refresh that joined one would throw away the reading it exists to take.
@MainActor
final class PushDeviceSyncQueue {
    private var tail: Task<Void, Never>?
    private var joinableRefresh: Task<Void, Never>?
    private var joinableRefreshGeneration = 0
    private var generation = 0

    /// Joins the refresh already scheduled, or schedules one. A refresh scheduled behind a
    /// mutation still runs, and takes its reading after that mutation lands.
    func coalesce(_ work: @escaping @Sendable @MainActor () async -> Void) async {
        if let joinableRefresh {
            await joinableRefresh.value
            return
        }

        await schedule(work, isRefresh: true).value
    }

    /// Queues behind everything already scheduled and hands back without waiting for any of it.
    @discardableResult
    func enqueue(_ work: @escaping @Sendable @MainActor () async -> Void) -> Task<Void, Never> {
        schedule(work, isRefresh: false)
    }

    @discardableResult
    private func schedule(
        _ work: @escaping @Sendable @MainActor () async -> Void,
        isRefresh: Bool
    ) -> Task<Void, Never> {
        let precedingSync = tail
        generation += 1
        let scheduledGeneration = generation

        let task = Task { @MainActor in
            _ = await precedingSync?.value
            await work()
            self.finish(scheduledGeneration)
        }

        tail = task
        if isRefresh {
            joinableRefresh = task
            joinableRefreshGeneration = scheduledGeneration
        }

        return task
    }

    private func finish(_ finishedGeneration: Int) {
        if generation == finishedGeneration {
            tail = nil
        }

        if joinableRefreshGeneration == finishedGeneration {
            joinableRefresh = nil
        }
    }
}
