import Testing
@testable import AscendApp

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

        await coordinator.suspendAndDrain()
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
        await coordinator.suspendAndDrain()
        coordinator.resumeLatest()
        _ = await runIterator.next()
        await coordinator.suspendAndDrain()

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
        await coordinator.suspendAndDrain()

        #expect(firstFinished)
        #expect(replacementRan == false)
    }
}
