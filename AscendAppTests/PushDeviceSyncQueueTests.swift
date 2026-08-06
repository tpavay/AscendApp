import Testing
@testable import AscendApp

/// Two `registerPushDevice` calls in flight at once contend on the same Firestore documents, so
/// what this suite watches is that nothing the app does can put two there.
@MainActor
struct PushDeviceSyncQueueTests {
    @Test("Launch's several triggers join one run rather than starting their own")
    func concurrentCoalescingJoinsTheRunAlreadyUnderWay() async {
        let queue = PushDeviceSyncQueue()
        let work = GatedSyncWork()

        let first = Task { await queue.coalesce { await work.run() } }
        await settle()
        let second = Task { await queue.coalesce { await work.run() } }
        let third = Task { await queue.coalesce { await work.run() } }
        await settle()

        #expect(work.startCount == 1)

        work.releaseAll()
        await first.value
        await second.value
        await third.value

        #expect(work.startCount == 1)
        #expect(work.finishCount == 1)
    }

    @Test("A sync whose inputs changed queues behind the running one instead of racing it")
    func enqueuedSyncsRunOneAtATime() async {
        let queue = PushDeviceSyncQueue()
        let work = GatedSyncWork()

        queue.enqueue { await work.run() }
        queue.enqueue { await work.run() }
        await settle()

        // The second is waiting its turn, not overlapping the first.
        #expect(work.startCount == 1)

        work.releaseAll()
        await settle()

        #expect(work.startCount == 2)
        #expect(work.overlapped == false)

        work.releaseAll()
        await settle()

        #expect(work.finishCount == 2)
        #expect(work.overlapped == false)
    }

    @Test("Queueing a sync hands back before the sync has run")
    func enqueueNeverWaitsForTheServer() async {
        let queue = PushDeviceSyncQueue()
        let work = GatedSyncWork()

        queue.enqueue { await work.run() }

        // The caller is already past the queue - this is what keeps a tap from waiting on
        // callables before the screen it asked for opens.
        #expect(work.startCount == 0)
        #expect(work.finishCount == 0)

        await settle()
        #expect(work.startCount == 1)
        #expect(work.finishCount == 0)

        work.releaseAll()
        await settle()

        #expect(work.finishCount == 1)
    }

    @Test("A sync queued while one is running still runs after it")
    func aQueuedSyncFollowsACoalescedOne() async {
        let queue = PushDeviceSyncQueue()
        let work = GatedSyncWork()

        let coalesced = Task { await queue.coalesce { await work.run() } }
        await settle()
        queue.enqueue { await work.run() }
        await settle()

        #expect(work.startCount == 1)

        work.releaseAll()
        await coalesced.value
        await settle()

        #expect(work.startCount == 2)
        #expect(work.overlapped == false)

        work.releaseAll()
        await settle()
    }

    private func settle() async {
        for _ in 0..<8 {
            await Task.yield()
        }
    }
}

/// Synchronization that parks until the test lets it finish, so overlap is observable.
@MainActor
private final class GatedSyncWork {
    private(set) var startCount = 0
    private(set) var finishCount = 0
    private(set) var overlapped = false

    private var isRunning = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run() async {
        if isRunning {
            overlapped = true
        }
        isRunning = true
        startCount += 1

        await withCheckedContinuation { waiters.append($0) }

        isRunning = false
        finishCount += 1
    }

    func releaseAll() {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}
