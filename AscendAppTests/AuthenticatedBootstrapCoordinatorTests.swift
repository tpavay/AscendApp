import Testing
@testable import AscendApp

/// A bound far past any scheduling delay, for the tests that assert what a drain which *finished*
/// does. The shipped bound is wall-clock, and a parallel test run can starve this drain's
/// main-actor hop for longer than five seconds - so asserting against the default would be
/// asserting that the machine won a race, not that the coordinator drained.
private let unraceableDrainBound: Duration = .seconds(3_600)

@MainActor
struct AuthenticatedBootstrapCoordinatorTests {
    @Test("Account deletion drains an old bootstrap before local cleanup", .bug(id: 389))
    func accountDeletionDrainsOldBootstrap() async {
        let coordinator = AuthenticatedBootstrapCoordinator()
        let started = AsyncStream<Void>.makeStream()
        var didFinishCancellation = false
        var didWriteDeletedOwnersData = false

        coordinator.schedule {
            defer { didFinishCancellation = true }
            started.continuation.yield()

            while Task.isCancelled == false {
                await Task.yield()
            }

            guard Task.isCancelled == false else { return }
            didWriteDeletedOwnersData = true
        }

        var startedIterator = started.stream.makeAsyncIterator()
        _ = await startedIterator.next()

        await coordinator.suspendAndDrain(timeout: unraceableDrainBound)
        coordinator.discard()

        #expect(didWriteDeletedOwnersData == false)
        #expect(didFinishCancellation)
    }

    @Test("A pre-deletion failure can resume the current account bootstrap", .bug(id: 389))
    func failedDeletionCanResumeLatestBootstrap() async {
        let coordinator = AuthenticatedBootstrapCoordinator()
        let runs = AsyncStream<Void>.makeStream()
        var runCount = 0

        coordinator.schedule {
            runCount += 1
            runs.continuation.yield()
        }
        var runIterator = runs.stream.makeAsyncIterator()
        _ = await runIterator.next()
        await coordinator.suspendAndDrain(timeout: unraceableDrainBound)
        coordinator.resumeLatest()
        _ = await runIterator.next()
        await coordinator.suspendAndDrain(timeout: unraceableDrainBound)

        #expect(runCount == 2)
    }

    @Test("Deletion drains bootstrap work superseded before deletion began", .bug(id: 389))
    func deletionDrainsSupersededBootstrapWork() async {
        let coordinator = AuthenticatedBootstrapCoordinator()
        let firstStarted = AsyncStream<Void>.makeStream()
        var firstFinished = false
        var replacementRan = false

        coordinator.schedule {
            defer { firstFinished = true }
            firstStarted.continuation.yield()

            while Task.isCancelled == false {
                await Task.yield()
            }
        }

        var firstStartedIterator = firstStarted.stream.makeAsyncIterator()
        _ = await firstStartedIterator.next()

        coordinator.schedule {
            replacementRan = true
        }
        await coordinator.suspendAndDrain(timeout: unraceableDrainBound)

        #expect(firstFinished)
        #expect(replacementRan == false)
    }

    @Test("A drain that outlives its bound does not stall deletion", .bug(id: 389))
    func drainReturnsWhenSessionWorkOutlivesItsBound() async {
        let diagnostics = SpyDiagnosticsRecorder()
        let reporter = RecordingCrashlyticsReporter()
        let coordinator = AuthenticatedBootstrapCoordinator(
            diagnostics: diagnostics,
            telemetry: makeTestTelemetry(reporter: reporter)
        )
        let started = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let releaseStream = release.stream

        coordinator.schedule {
            started.continuation.yield()

            // Stands in for a media upload: the per-item work runs in an inner task that does not
            // inherit the chain's cancellation, and awaiting it is not a cancellation point either.
            let inFlightUpload = Task<Void, Never> {
                var iterator = releaseStream.makeAsyncIterator()
                _ = await iterator.next()
            }
            await inFlightUpload.value
        }

        var startedIterator = started.stream.makeAsyncIterator()
        _ = await startedIterator.next()

        let didDrain = await coordinator.suspendAndDrain(timeout: .milliseconds(50))

        #expect(didDrain == false)
        // Timing out is safe only because nothing new may start behind it.
        #expect(coordinator.isSuspended)

        // The one state in which a straggler could still write inside deletion's staged window has
        // to leave a trace, or a recurrence in the field is unattributable.
        let timeouts = diagnostics.events.filter {
            $0.name == AuthenticatedBootstrapCoordinator.drainTimeoutCode
        }
        #expect(timeouts.count == 1)
        #expect(timeouts.first?.level == .warning)
        #expect(timeouts.first?.mirrorToCrashlytics == true)

        // And it has to leave that trace somewhere that outlives the deletion reporting it: the
        // diagnostic's ring buffer is wiped two steps later and its Crashlytics half is a
        // breadcrumb, so only the non-fatal reaches a dashboard when deletion then succeeds.
        let nonFatals = reporter.recordedErrors.filter {
            $0.code == AuthenticatedBootstrapCoordinator.drainTimeoutCode
        }
        #expect(nonFatals.count == 1)
        #expect(nonFatals.first?.context == TelemetryManager.ErrorContext.auth.rawValue)
        #expect(nonFatals.first?.additionalInfo?["timeout_seconds"] != nil)

        release.continuation.yield()
        release.continuation.finish()
    }

    @Test("Deletion cancels and drains writers outside the bootstrap chain", .bug(id: 389))
    func deletionQuiescesAutonomousSessionWorkers() async {
        let diagnostics = SpyDiagnosticsRecorder()
        let reporter = RecordingCrashlyticsReporter()
        let coordinator = AuthenticatedBootstrapCoordinator(
            diagnostics: diagnostics,
            telemetry: makeTestTelemetry(reporter: reporter)
        )
        let worker = RecordingSessionWorker()

        let didDrain = await coordinator.suspendAndDrain(
            autonomousWorkers: [worker],
            timeout: unraceableDrainBound
        )

        #expect(didDrain)
        #expect(worker.didCancel)
        #expect(worker.didDrainAfterCancel == true)
        // A drain that finished is not a defect, so it must not report one.
        #expect(diagnostics.events.isEmpty)
        #expect(reporter.recordedErrors.isEmpty)
    }

    @Test("Resuming and discarding both reopen the gate for autonomous writers", .bug(id: 389))
    func gateReopensAfterDeletionResolves() async {
        let coordinator = AuthenticatedBootstrapCoordinator()

        coordinator.schedule {}
        await coordinator.suspendAndDrain(timeout: unraceableDrainBound)
        #expect(coordinator.isSuspended)

        coordinator.resumeLatest()
        #expect(coordinator.isSuspended == false)

        await coordinator.suspendAndDrain(timeout: unraceableDrainBound)
        coordinator.discard()
        #expect(coordinator.isSuspended == false)
    }
}

/// Stands in for a HealthKit-observer import pass or a media upload queue: account-scoped work the
/// bootstrap chain does not own.
@MainActor
private final class RecordingSessionWorker: AuthenticatedSessionWorker {
    private(set) var didCancel = false
    private(set) var didDrainAfterCancel: Bool?

    func cancelInFlightWork() {
        didCancel = true
    }

    func drainInFlightWork() async {
        didDrainAfterCancel = didCancel
    }
}
