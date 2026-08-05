import Foundation

/// Owns the one authenticated bootstrap task allowed to touch account-scoped state.
///
/// Account deletion suspends and drains this task before its first destructive remote step. That
/// ordering prevents an already-started hydration or upload from saving the deleted account's data
/// after the local store has been emptied.
@MainActor
final class AuthenticatedBootstrapCoordinator {
    static let shared = AuthenticatedBootstrapCoordinator()

    typealias Operation = @MainActor () async -> Void

    private var activeTask: Task<Void, Never>?
    private var latestOperation: Operation?
    private var isSuspended = false

    init() {}

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

    /// Cancels the current task and waits for it to stop touching local or remote account state.
    func suspendAndDrain() async {
        isSuspended = true
        let task = activeTask
        activeTask = nil
        task?.cancel()
        await task?.value
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
