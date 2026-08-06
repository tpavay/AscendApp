import Foundation

/// Account-scoped local work that runs on its own schedule rather than inside the bootstrap chain.
///
/// A HealthKit observer firing an import pass is the motivating case: nothing about it is reachable
/// from `AuthenticatedBootstrapCoordinator.schedule`, yet it writes the signed-in account's rows
/// into the same `ModelContext` that deletion is emptying.
@MainActor
protocol AuthenticatedSessionWorker: AnyObject {
    /// Stops in-flight work. Returns immediately; cancellation is cooperative.
    func cancelInFlightWork()

    /// Waits for the cancelled work to stop touching account-scoped state.
    func drainInFlightWork() async
}

/// Owns the one authenticated bootstrap task allowed to touch account-scoped state, and gates every
/// other writer of that state while deletion is running.
///
/// Account deletion suspends and drains before its first destructive remote step. That ordering
/// prevents an already-started hydration, import, or upload from saving the deleted account's data
/// after the local store has been emptied. `isSuspended` is the second half of the guarantee:
/// draining only stops what has already started, so autonomous writers ask this before starting more.
@MainActor
final class AuthenticatedBootstrapCoordinator {
    static let shared = AuthenticatedBootstrapCoordinator()

    typealias Operation = @MainActor () async -> Void

    /// How long a drain waits before it proceeds without the stragglers.
    ///
    /// Deletion drains from its non-interactive phase, where there is no one to tell that the app
    /// is waiting, and the work being drained includes media uploads whose per-item retries can run
    /// for minutes and whose inner task does not inherit the outer cancellation.
    static let drainTimeout: Duration = .seconds(5)

    private var activeTask: Task<Void, Never>?
    private var latestOperation: Operation?
    private let diagnostics: any AppDiagnosticsRecording
    private(set) var isSuspended = false

    init(diagnostics: any AppDiagnosticsRecording = AppDiagnosticsRecorder.shared) {
        self.diagnostics = diagnostics
    }

    func schedule(_ operation: @escaping Operation) {
        latestOperation = operation
        guard !isSuspended else { return }

        let previousTask = activeTask
        previousTask?.cancel()
        activeTask = Task {
            // Cancellation is cooperative. Drain every superseded operation before starting its
            // replacement so `activeTask` remains a complete chain that deletion can await.
            await previousTask?.value
            guard Task.isCancelled == false else { return }
            await operation()
        }
    }

    /// Cancels account-scoped work and waits, up to `timeout`, for it to stop touching local or
    /// remote account state.
    ///
    /// Bounded on purpose, and safe to time out: `isSuspended` stays true so nothing new starts,
    /// everything drained here is already cancelled, and each step of the bootstrap chain re-checks
    /// cancellation and session identity before it writes.
    ///
    /// Timing out is recorded here rather than left to callers. It is the one state in which a
    /// straggler could still write inside deletion's staged window, so a recurrence in the field has
    /// to be attributable - and a caller that can only proceed anyway has no decision to make with
    /// the result.
    ///
    /// - Returns: whether the work stopped within the bound.
    @discardableResult
    func suspendAndDrain(
        autonomousWorkers: [any AuthenticatedSessionWorker] = [],
        timeout: Duration = AuthenticatedBootstrapCoordinator.drainTimeout
    ) async -> Bool {
        isSuspended = true

        let task = activeTask
        activeTask = nil
        task?.cancel()

        for worker in autonomousWorkers {
            worker.cancelInFlightWork()
        }

        let drain = Task { @MainActor in
            await task?.value

            for worker in autonomousWorkers {
                await worker.drainInFlightWork()
            }
        }

        let didDrain = await completed(drain, within: timeout)

        if didDrain == false {
            diagnostics.record(
                "authenticated_session_drain_timed_out",
                level: .warning,
                details: [
                    "timeout_seconds": "\(timeout.components.seconds)",
                    "autonomous_workers": "\(autonomousWorkers.count)"
                ],
                mirrorToCrashlytics: true
            )
        }

        return didDrain
    }

    /// Restarts the last requested bootstrap when deletion stopped before the auth account did.
    func resumeLatest() {
        guard isSuspended else { return }
        isSuspended = false

        guard let latestOperation else { return }
        schedule(latestOperation)
    }

    /// Drops all work belonging to an auth account that no longer exists.
    func discard() {
        activeTask?.cancel()
        activeTask = nil
        latestOperation = nil
        isSuspended = false
    }
}

/// Waits for `task`, giving up after `timeout` and reporting whether it finished.
///
/// Parks on a continuation rather than racing inside a task group: awaiting a `Task<Void, Never>`
/// is not interruptible by the awaiting task's own cancellation, so a group would keep waiting for
/// exactly the work the bound exists to escape.
private func completed(_ task: Task<Void, Never>, within timeout: Duration) async -> Bool {
    await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
        let resumer = BoundedWaitResumer(continuation)

        Task {
            await task.value
            resumer.resume(returning: true)
        }

        Task {
            try? await Task.sleep(for: timeout)
            resumer.resume(returning: false)
        }
    }
}

/// Resumes a continuation exactly once, whichever of the drain and its timeout wins.
private final class BoundedWaitResumer: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: Bool) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(returning: value)
    }
}
