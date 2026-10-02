import Testing
@testable import AscendApp

/// A step that suspends until the test releases it, so a test can hold one part of the chain
/// open and see what the rest did meanwhile.
@MainActor
private final class HeldStep {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReleased = false
    private(set) var didStart = false

    func run() async {
        didStart = true
        guard !isReleased else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class ChainLog {
    var events: [String] = []
    var isCurrentSession = true
}

@MainActor
struct AuthenticatedSessionWorkChainTests {
    private func chain(
        log: ChainLog,
        hydrate: @escaping AuthenticatedSessionWorkChain.Step = {},
        entitlements: @escaping AuthenticatedSessionWorkChain.Step = {},
        uploads: @escaping AuthenticatedSessionWorkChain.Step = {}
    ) -> AuthenticatedSessionWorkChain {
        AuthenticatedSessionWorkChain(
            hydrateBlockList: { await hydrate(); log.events.append("hydrated") },
            refreshEntitlements: { await entitlements(); log.events.append("entitlements") },
            processPendingUploads: { await uploads(); log.events.append("uploads") },
            bootstrapLocalState: { log.events.append("bootstrap") },
            synchronizePushDevice: { log.events.append("push") },
            isCurrentSession: { log.isCurrentSession }
        )
    }

    /// Waits for main-actor work started elsewhere to reach `condition`, without a wall clock.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<1_000 where !condition() {
            await Task.yield()
        }
    }

    @Test("The block list loads while a slow RevenueCat refresh is still out")
    func blockListHydratesWhileEntitlementsAreSuspended() async {
        let log = ChainLog()
        let entitlements = HeldStep()
        let run = Task { await chain(log: log, entitlements: { await entitlements.run() }).run() }

        await settle { log.events.contains("hydrated") }
        #expect(entitlements.didStart)
        #expect(log.events == ["hydrated"], "climbers stay masked as blocked until this read lands")

        entitlements.release()
        await run.value
        #expect(log.events == ["hydrated", "entitlements", "uploads", "bootstrap", "push"])
    }

    @Test("The block list loads while the media-upload sweep is still out")
    func blockListHydratesWhileUploadsAreSuspended() async {
        let log = ChainLog()
        let hydrate = HeldStep()
        let uploads = HeldStep()
        let run = Task { await chain(log: log, hydrate: { await hydrate.run() }, uploads: { await uploads.run() }).run() }

        await settle { uploads.didStart }
        hydrate.release()
        await settle { log.events.contains("hydrated") }
        #expect(log.events == ["entitlements", "hydrated"])

        uploads.release()
        await run.value
        #expect(log.events == ["entitlements", "hydrated", "uploads", "bootstrap", "push"])
    }

    @Test("Local bootstrap waits for a block list that answers last")
    func bootstrapWaitsForASlowBlockList() async {
        let log = ChainLog()
        let hydrate = HeldStep()
        let run = Task { await chain(log: log, hydrate: { await hydrate.run() }).run() }

        await settle { log.events.contains("uploads") }
        #expect(log.events == ["entitlements", "uploads"], "bootstrap must not start on an unhydrated session")

        hydrate.release()
        await run.value
        #expect(log.events == ["entitlements", "uploads", "hydrated", "bootstrap", "push"])
    }

    @Test("A session that changed while the head ran stops before the local bootstrap")
    func sessionChangeStopsTheChain() async {
        let log = ChainLog()
        let entitlements = HeldStep()
        let run = Task { await chain(log: log, entitlements: { await entitlements.run() }).run() }

        await settle { log.events.contains("hydrated") }
        log.isCurrentSession = false
        entitlements.release()
        await run.value

        #expect(log.events == ["hydrated", "entitlements"])
    }
}
