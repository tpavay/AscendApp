import Foundation
import Testing
@testable import AscendApp

@MainActor
struct AppAccessReconciliationServiceTests {
    @Test
    func aDerivedAnswerSatisfiesTheClientSpacing() async {
        let invoker = ReconciliationInvokerSpy(outcomes: [.active, .active])
        let clock = TestClock()
        let service = makeService(invoker: invoker, clock: clock)

        await service.reconcileAppAccess(force: false)
        await service.reconcileAppAccess(force: false)

        #expect(invoker.callCount == 1)
    }

    @Test
    func aThrottledRefusalBacksOffWithoutCountingAsAnAnswer() async {
        let invoker = ReconciliationInvokerSpy(outcomes: [.throttled, .active])
        let clock = TestClock()
        let service = makeService(invoker: invoker, clock: clock)

        await service.reconcileAppAccess(force: false)
        // A refusal must not let every foreground issue another call...
        await service.reconcileAppAccess(force: false)
        #expect(invoker.callCount == 1)

        // ...and it must not buy the full success spacing either.
        clock.advance(by: 61)
        await service.reconcileAppAccess(force: false)
        #expect(invoker.callCount == 2)
    }

    @Test
    func anUnrecognizedStatusBacksOffWithoutCountingAsAnAnswer() async {
        let invoker = ReconciliationInvokerSpy(outcomes: [.unrecognized, .inactive])
        let clock = TestClock()
        let service = makeService(invoker: invoker, clock: clock)

        await service.reconcileAppAccess(force: false)
        await service.reconcileAppAccess(force: false)
        #expect(invoker.callCount == 1)

        clock.advance(by: 61)
        await service.reconcileAppAccess(force: false)
        #expect(invoker.callCount == 2)
    }

    @Test
    func aFailedCallBacksOffAndThenRecovers() async {
        let invoker = ReconciliationInvokerSpy(outcomes: [.active])
        invoker.errors = [ReconciliationFailure()]
        let clock = TestClock()
        let service = makeService(invoker: invoker, clock: clock)

        await service.reconcileAppAccess(force: false)
        // An outage must not turn every trigger into another callable invocation.
        await service.reconcileAppAccess(force: false)
        #expect(invoker.callCount == 1)

        clock.advance(by: 31)
        await service.reconcileAppAccess(force: false)
        #expect(invoker.callCount == 2)
    }

    @Test
    func anExplicitRestoreStillRecoversInsideAFailureBackoff() async {
        let invoker = ReconciliationInvokerSpy(outcomes: [.active])
        invoker.errors = [ReconciliationFailure()]
        let service = makeService(invoker: invoker, clock: TestClock())

        await service.reconcileAppAccess(force: false)
        await service.reconcileAppAccess(force: true)

        #expect(invoker.callCount == 2)
    }

    @Test
    func anExplicitRestoreStillRecoversInsideAThrottleBackoff() async {
        let invoker = ReconciliationInvokerSpy(outcomes: [.throttled, .active])
        let service = makeService(invoker: invoker, clock: TestClock())

        await service.reconcileAppAccess(force: false)
        await service.reconcileAppAccess(force: true)

        #expect(invoker.callCount == 2)
    }

    @Test
    func spacingExpiresAndAllowsAnotherAnswer() async {
        let invoker = ReconciliationInvokerSpy(outcomes: [.active, .inactive])
        let clock = TestClock()
        let service = makeService(invoker: invoker, clock: clock)

        await service.reconcileAppAccess(force: false)
        clock.advance(by: 301)
        await service.reconcileAppAccess(force: false)

        #expect(invoker.callCount == 2)
    }

    @Test
    func aForcedRestoreBypassesTheClientSpacing() async {
        let invoker = ReconciliationInvokerSpy(outcomes: [.active, .active])
        let service = makeService(invoker: invoker, clock: TestClock())

        await service.reconcileAppAccess(force: false)
        await service.reconcileAppAccess(force: true)

        #expect(invoker.callCount == 2)
    }

    @Test
    func overlappingCallersNeverLeaveAStaleInFlightMarker() async {
        let invoker = ReconciliationInvokerSpy(outcomes: [.active, .active, .active])
        let clock = TestClock()
        let service = makeService(invoker: invoker, clock: clock)

        async let first: Void = service.reconcileAppAccess(force: true)
        async let second: Void = service.reconcileAppAccess(force: true)
        _ = await (first, second)

        await service.reconcileAppAccess(force: false)

        #expect(invoker.callCount == 2)
    }

    @Test
    func aSignedOutDeviceNeverReachesTheServer() async {
        let invoker = ReconciliationInvokerSpy(outcomes: [.active])
        let service = AppAccessReconciliationService(
            invoker: invoker,
            currentUserID: { nil },
            clock: { Date(timeIntervalSince1970: 0) }
        )

        await service.reconcileAppAccess(force: true)

        #expect(invoker.callCount == 0)
    }

    @Test
    func aDifferentSignedInUserIsAlwaysReconciled() async {
        let invoker = ReconciliationInvokerSpy(outcomes: [.active, .active])
        var userID = "user-a"
        let service = AppAccessReconciliationService(
            invoker: invoker,
            currentUserID: { userID },
            clock: { Date(timeIntervalSince1970: 0) }
        )

        await service.reconcileAppAccess(force: false)
        userID = "user-b"
        await service.reconcileAppAccess(force: false)

        #expect(invoker.callCount == 2)
    }

    private func makeService(
        invoker: ReconciliationInvokerSpy,
        clock: TestClock
    ) -> AppAccessReconciliationService {
        AppAccessReconciliationService(
            invoker: invoker,
            currentUserID: { "user-a" },
            clock: { clock.now }
        )
    }
}

private struct ReconciliationFailure: Error { }

private final class TestClock: @unchecked Sendable {
    private(set) var now = Date(timeIntervalSince1970: 1_000)

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}

@MainActor
private final class ReconciliationInvokerSpy: AppAccessReconciliationInvoking {
    private(set) var callCount = 0
    var errors: [any Error] = []
    private var outcomes: [AppAccessReconciliationOutcome]

    init(outcomes: [AppAccessReconciliationOutcome]) {
        self.outcomes = outcomes
    }

    func invokeReconciliation() async throws -> AppAccessReconciliationOutcome {
        callCount += 1

        if !errors.isEmpty {
            throw errors.removeFirst()
        }

        return outcomes.isEmpty ? .active : outcomes.removeFirst()
    }
}
