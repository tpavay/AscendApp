import Foundation

/// Account-scoped local work that runs on its own schedule rather than inside the bootstrap chain.
///
/// An Apple Health enrichment sweep is the motivating case: it starts on its own schedule - a
/// foreground, a tab return - so nothing about it is reachable from
/// `AuthenticatedBootstrapCoordinator.schedule`, yet it writes the signed-in account's rows into
/// the same `ModelContext` that deletion is emptying.
@MainActor
protocol AuthenticatedSessionWorker: AnyObject {
    /// Stops in-flight work. Returns immediately; cancellation is cooperative.
    func cancelInFlightWork()

    /// Waits for the cancelled work to stop touching account-scoped state.
    func drainInFlightWork() async
}

/// The autonomous writers of account-scoped state, in one place.
///
/// Both ends of a session read this list - account deletion drains it before it empties the store,
/// and sign-out stops it before the next climber signs in - so a worker added here is covered by
/// both without a second list to keep in step. Computed rather than stored, because each singleton
/// resolves this coordinator during its own initialisation.
@MainActor
enum AutonomousSessionWorkers {
    static var all: [any AuthenticatedSessionWorker] {
        [
            AppleHealthEnrichmentService.shared,
            MediaUploadManager.shared
        ]
    }
}

/// Owns the one authenticated bootstrap task allowed to touch account-scoped state, and gates every
/// other writer of that state while deletion is running.
///
/// Account deletion suspends and drains before its first destructive remote step. That ordering
/// prevents an already-started hydration, enrichment pass, or upload from saving the deleted
/// account's data after the local store has been emptied. `isSuspended` is the second half of the
/// guarantee: draining only stops what has already started, so autonomous writers ask this before
/// starting more.
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

    /// One identifier for both the diagnostic and the non-fatal, so a field report is one search.
    static let drainTimeoutCode = "authenticated_session_drain_timed_out"

    private var activeTask: Task<Void, Never>?
    private var latestOperation: Operation?
    private let diagnostics: any AppDiagnosticsRecording
    private let telemetry: TelemetryManager
    private(set) var isSuspended = false

    init(
        diagnostics: any AppDiagnosticsRecording = AppDiagnosticsRecorder.shared,
        telemetry: TelemetryManager = .shared
    ) {
        self.diagnostics = diagnostics
        self.telemetry = telemetry
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
    /// It is recorded as a non-fatal, not only as a diagnostic, because neither half of the
    /// diagnostic survives the flow it reports on: the ring buffer lives in the app's UserDefaults
    /// domain that deletion wipes two steps later, and the Crashlytics mirror is a breadcrumb that
    /// only ships attached to some later crash. A deletion that times out and then succeeds is
    /// exactly the case that must still reach the dashboard.
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
            let details = [
                "timeout_seconds": "\(timeout.components.seconds)",
                "autonomous_workers": "\(autonomousWorkers.count)"
            ]

            diagnostics.record(
                Self.drainTimeoutCode,
                level: .warning,
                details: details,
                mirrorToCrashlytics: true
            )
            telemetry.recordError(
                AuthenticatedSessionDrainTimeout(),
                context: .auth,
                code: Self.drainTimeoutCode,
                additionalInfo: details
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

    /// Ends the session the signed-out account owned.
    ///
    /// Draining the bootstrap chain is not enough on its own, and neither is a wipe of the local
    /// store: an autonomous worker schedules its own next wake-up, so one armed under the previous
    /// climber keeps its captured store and its work list and fires after the account has changed.
    /// Enrichment's timer sleeps for hours between passes, and the write it wakes up to make is
    /// attributed to whoever is signed in when it lands.
    ///
    /// Deliberately does not touch `isSuspended`: deletion owns that flag, and deleting the auth
    /// account routes through here partway through deletion's own sweep.
    func endAuthenticatedSession(
        autonomousWorkers: [any AuthenticatedSessionWorker] = AutonomousSessionWorkers.all
    ) {
        activeTask?.cancel()
        activeTask = nil
        latestOperation = nil

        for worker in autonomousWorkers {
            worker.cancelInFlightWork()
        }
    }

    /// Drops all work belonging to an auth account that no longer exists.
    func discard() {
        activeTask?.cancel()
        activeTask = nil
        latestOperation = nil
        isSuspended = false
    }
}

/// The non-fatal raised when a drain gives up and deletion proceeds without its stragglers.
struct AuthenticatedSessionDrainTimeout: Error {}

/// Waits for `task`, giving up after `timeout` and reporting whether it finished.
///
/// Parks on a continuation rather than racing inside a task group: awaiting a `Task<Void, Never>`
/// is not interruptible by the awaiting task's own cancellation, so a group would keep waiting for
/// exactly the work the bound exists to escape.
private func completed(_ task: Task<Void, Never>, within timeout: Duration) async -> Bool {
    var timer: Task<Void, Never>?

    let didComplete = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
        let resumer = BoundedWaitResumer(continuation)

        Task {
            await task.value
            resumer.resume(returning: true)
        }

        timer = Task {
            try? await Task.sleep(for: timeout)
            resumer.resume(returning: false)
        }
    }

    // A drain that won the race leaves nothing behind still counting down against it.
    timer?.cancel()
    return didComplete
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
