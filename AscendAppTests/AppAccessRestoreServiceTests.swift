import Foundation
import Testing
@testable import AscendApp

@MainActor
struct AppAccessRestoreServiceTests {
    private static let identityUserID = "restore-user"
    private let identity = MonetizationIdentityTransition(
        revision: 11,
        userID: Self.identityUserID
    )

    @Test
    func cancellingOneWaiterDoesNotCancelTheSharedProviderOrAnotherWaiter() async {
        let restorer = SuspendingRestoreProvider(identity: identity)
        let sleeps = ControlledRestoreSleep()
        let service = makeService(restorer: restorer, sleep: sleeps.sleep)

        let cancelledWaiter = Task { await service.restore() }
        await restorer.waitUntilStarted()
        let successfulWaiter = Task { await service.restore() }
        await sleeps.waitUntilCallCount(2)

        cancelledWaiter.cancel()
        let cancelled = await cancelledWaiter.value
        #expect(cancelled.isFailure(AppAccessRestoreError.cancelled))

        restorer.complete(with: .active(["app_access"]))
        let restored = await successfulWaiter.value

        #expect(restored.entitlementIDs == ["app_access"])
        #expect(restorer.restoreCount == 1)
        #expect(restorer.capturedIdentity == identity)
        #expect(service.activeRestoreWaiterCount == 0)
        #expect(sleeps.activeContinuationCount == 0)
    }

    @Test
    func retryAfterTimeoutJoinsProviderWithAFreshDeadline() async {
        let restorer = SuspendingRestoreProvider(identity: identity)
        let sleeps = ControlledRestoreSleep()
        let service = makeService(restorer: restorer, sleep: sleeps.sleep)

        let firstWaiter = Task { await service.restore() }
        await restorer.waitUntilStarted()
        await sleeps.waitUntilCallCount(1)
        sleeps.fire(call: 1)
        let first = await firstWaiter.value
        #expect(first.isFailure(AppAccessRestoreError.timedOut))
        #expect(restorer.restoreCount == 1)

        let retry = Task { await service.restore() }
        await sleeps.waitUntilCallCount(2)
        restorer.complete(with: .active(["app_access"]))
        let restored = await retry.value

        #expect(restored.entitlementIDs == ["app_access"])
        #expect(restorer.restoreCount == 1)
        #expect(service.activeRestoreWaiterCount == 0)
        #expect(sleeps.activeContinuationCount == 0)
    }

    @Test
    func missingSettledIdentityRefusesRestoreBeforeCallingProvider() async {
        let restorer = SuspendingRestoreProvider(identity: nil)
        let service = makeService(restorer: restorer)

        let outcome = await service.restore()

        #expect(outcome.isEntitlementUnconfirmedFailure)
        #expect(restorer.restoreCount == 0)
    }

    @Test
    func aNewIdentityWaitsForTheOldProviderLaneThenStartsOnlyIfStillExact() async {
        let restorer = IdentitySwitchingRestoreProvider(identity: identity)
        let sink = IdentityAttributingTelemetrySink()
        let telemetry = makeAttributingTelemetry(sink: sink, userID: Self.identityUserID)
        let sleeps = ControlledRestoreSleep()
        let service = AppAccessRestoreService(
            telemetry: telemetry,
            entitlementID: "app_access",
            restorer: { restorer },
            sleep: sleeps.sleep
        )

        let oldAccount = Task { await service.restore() }
        await restorer.waitUntilCallCount(1)

        let newUserID = "new-user"
        let newIdentity = MonetizationIdentityTransition(revision: 12, userID: newUserID)
        telemetry.setUserId(newUserID)
        restorer.identityGeneration = newIdentity
        let newAccount = Task { await service.restore() }
        await sleeps.waitUntilCallCount(2)

        #expect(restorer.capturedIdentities == [identity])
        restorer.complete(identity: identity, with: .active(["app_access"]))
        #expect(await oldAccount.value.isEntitlementUnconfirmedFailure)

        await restorer.waitUntilCallCount(2)
        await sleeps.waitUntilCallCount(3)
        #expect(restorer.capturedIdentities == [identity, newIdentity])

        restorer.complete(identity: newIdentity, with: .active(["app_access"]))
        #expect(await newAccount.value.entitlementIDs == ["app_access"])
        #expect(service.activeRestoreWaiterCount == 0)
        #expect(sleeps.activeContinuationCount == 0)
        let attributions = sink.attributions
        #expect(attributions.map(\.name) == [
            "revenuecat_restore_started",
            "revenuecat_restore_started",
            "revenuecat_restore_completed"
        ])
        #expect(attributions.map(\.userID) == [
            Self.identityUserID,
            newUserID,
            newUserID
        ])
        let terminals = attributions.filter { $0.name != "revenuecat_restore_started" }
        #expect(terminals.count == 1)
        #expect(terminals[0].parameters["outcome"] == .string("success"))
        #expect(terminals[0].parameters["identity_match"] == .bool(true))
        #expect(attributions.allSatisfy {
            $0.parameters["user_id"] == nil &&
                $0.parameters["identity_revision"] == nil
        })
    }

    @Test
    func coalescedWaitersEachEmitOneStartAndOneTerminalWhileSharingProviderWork() async {
        let restorer = SuspendingRestoreProvider(identity: identity)
        let sink = IdentityAttributingTelemetrySink()
        let telemetry = makeAttributingTelemetry(sink: sink, userID: Self.identityUserID)
        let sleeps = ControlledRestoreSleep()
        let service = AppAccessRestoreService(
            telemetry: telemetry,
            entitlementID: "app_access",
            restorer: { restorer },
            sleep: sleeps.sleep
        )

        let first = Task { await service.restore() }
        await restorer.waitUntilStarted()
        let second = Task { await service.restore() }
        await sleeps.waitUntilCallCount(2)
        restorer.complete(with: .active(["app_access"]))
        _ = await (first.value, second.value)

        #expect(restorer.restoreCount == 1)
        let attributions = sink.attributions
        #expect(attributions.filter { $0.name == "revenuecat_restore_started" }.count == 2)
        #expect(attributions.filter { $0.name == "revenuecat_restore_completed" }.count == 2)
        #expect(attributions.allSatisfy { $0.userID == Self.identityUserID })
        #expect(attributions.allSatisfy {
            $0.parameters["user_id"] == nil &&
                $0.parameters["identity_revision"] == nil
        })
        let attemptIDs = attributions.compactMap { attribution -> String? in
            guard case .string(let value) = attribution.parameters["restore_attempt_id"] else {
                return nil
            }
            return value
        }
        #expect(Set(attemptIDs).count == 2)
        for attemptID in Set(attemptIDs) {
            #expect(attemptIDs.filter { $0 == attemptID }.count == 2)
        }
        #expect(service.activeRestoreWaiterCount == 0)
        #expect(sleeps.activeContinuationCount == 0)
    }

    @Test
    func neverReturningProviderLeavesNoWaiterObserversAfterRepeatedTimeoutsAndCancellations() async {
        let restorer = SuspendingRestoreProvider(identity: identity)
        let sink = IdentityAttributingTelemetrySink()
        let telemetry = makeAttributingTelemetry(sink: sink, userID: Self.identityUserID)
        let sleeps = ControlledRestoreSleep()
        let service = AppAccessRestoreService(
            telemetry: telemetry,
            entitlementID: "app_access",
            restorer: { restorer },
            timeout: .seconds(15),
            sleep: sleeps.sleep
        )

        for call in 1...3 {
            let context = AppAccessRestoreAnalyticsContext.appAccessGate(
                gateAttemptID: "gate-timeout-\(call)"
            )
            let attempt = Task { await service.restore(context: context) }
            await sleeps.waitUntilCallCount(call)
            sleeps.fire(call: call)
            #expect(await attempt.value.isFailure(AppAccessRestoreError.timedOut))
            #expect(service.activeRestoreWaiterCount == 0)
            #expect(sleeps.activeContinuationCount == 0)
        }

        for call in 4...6 {
            let context = AppAccessRestoreAnalyticsContext.appAccessGate(
                gateAttemptID: "gate-cancel-\(call)"
            )
            let attempt = Task { await service.restore(context: context) }
            await sleeps.waitUntilCallCount(call)
            attempt.cancel()
            #expect(await attempt.value.isFailure(AppAccessRestoreError.cancelled))
            #expect(service.activeRestoreWaiterCount == 0)
            #expect(sleeps.activeContinuationCount == 0)
        }

        #expect(restorer.restoreCount == 1)
        let attributions = sink.attributions
        let starts = attributions.filter { $0.name == "revenuecat_restore_started" }
        let terminals = attributions.filter { $0.name == "revenuecat_restore_failed" }
        #expect(starts.count == 6)
        #expect(terminals.count == 6)
        #expect(attributions.allSatisfy { $0.userID == Self.identityUserID })
        #expect(attributions.allSatisfy {
            $0.parameters["user_id"] == nil &&
                $0.parameters["identity_revision"] == nil
        })
        #expect(terminals.prefix(3).allSatisfy {
            $0.parameters["error_type"] == .string("restore_timed_out")
        })
        #expect(terminals.suffix(3).allSatisfy {
            $0.parameters["error_type"] == .string("restore_cancelled")
        })
        for start in starts {
            guard case .string(let attemptID)? = start.parameters["restore_attempt_id"] else {
                Issue.record("Restore start lacks an attempt identifier")
                continue
            }
            #expect(terminals.filter {
                $0.parameters["restore_attempt_id"] == .string(attemptID)
            }.count == 1)
            #expect(start.parameters["placement"] == .string("app_access_gate"))
            #expect(start.parameters["restore_source"] == .string("app_access_gate"))
            #expect(start.parameters["recovery_path"] == .string("restore"))
        }
    }

    private func makeService(
        restorer: SuspendingRestoreProvider,
        sleep: @escaping AppAccessRestoreService.Sleep = { try await Task.sleep(for: $0) }
    ) -> AppAccessRestoreService {
        AppAccessRestoreService(
            telemetry: makeTestTelemetry(
                sink: InMemoryTelemetrySink(destination: .analytics)
            ),
            entitlementID: "app_access",
            restorer: { restorer },
            timeout: .seconds(15),
            sleep: sleep
        )
    }

    private func makeAttributingTelemetry(
        sink: IdentityAttributingTelemetrySink,
        userID: String
    ) -> TelemetryManager {
        let telemetry = TelemetryManager(
            sinks: [sink],
            crashlyticsReporter: NoopCrashlyticsReporter(),
            collectionEnabledOverride: true,
            identityStore: makeTestIdentityStore()
        )
        telemetry.configure()
        telemetry.setUserId(userID)
        return telemetry
    }
}

private final class ControlledRestoreSleep: @unchecked Sendable {
    private let lock = NSLock()
    private var nextCall = 0
    private var continuations: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var observers: [CheckedContinuation<Void, Never>] = []

    func sleep(for duration: Duration) async throws {
        let call = lock.withLock { () -> Int in
            nextCall += 1
            let call = nextCall
            observers.forEach { $0.resume() }
            observers = []
            return call
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    lock.withLock { continuations[call] = continuation }
                }
            }
        } onCancel: {
            let continuation = lock.withLock { continuations.removeValue(forKey: call) }
            continuation?.resume(throwing: CancellationError())
        }
    }

    func fire(call: Int) {
        let continuation = lock.withLock { continuations.removeValue(forKey: call) }
        continuation?.resume()
    }

    var activeContinuationCount: Int {
        lock.withLock { continuations.count }
    }

    func waitUntilCallCount(_ expected: Int) async {
        if lock.withLock({ nextCall >= expected }) { return }
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock { () -> Bool in
                if nextCall >= expected { return true }
                observers.append(continuation)
                return false
            }
            if shouldResume { continuation.resume() }
        }
    }
}

private extension AppAccessRestoreOutcome {
    var entitlementIDs: Set<String>? {
        guard case .restored(let entitlementIDs) = self else { return nil }
        return entitlementIDs
    }

    func isFailure(_ expected: AppAccessRestoreError) -> Bool {
        guard case .failed(let error) = self,
              let restoreError = error as? AppAccessRestoreError else {
            return false
        }

        switch (restoreError, expected) {
        case (.cancelled, .cancelled), (.offline, .offline), (.timedOut, .timedOut):
            return true
        default:
            return false
        }
    }

    var isEntitlementUnconfirmedFailure: Bool {
        guard case .failed(let error) = self,
              let controllerError = error as? RevenueCatPurchaseControllerError,
              case .entitlementUnconfirmed = controllerError else {
            return false
        }
        return true
    }

}

@MainActor
private final class SuspendingRestoreProvider: PurchaseRestoring {
    let isRevenueCatConfigured = true
    let identityGeneration: MonetizationIdentityTransition?
    private(set) var restoreCount = 0
    private(set) var capturedIdentity: MonetizationIdentityTransition?

    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var completion: CheckedContinuation<MonetizationEntitlementState, Never>?

    init(identity: MonetizationIdentityTransition?) {
        identityGeneration = identity
    }

    func restorePurchases(
        for identity: MonetizationIdentityTransition
    ) async -> MonetizationEntitlementState {
        restoreCount += 1
        capturedIdentity = identity
        startWaiters.forEach { $0.resume() }
        startWaiters = []
        return await withCheckedContinuation { completion = $0 }
    }

    func restorePurchases() async -> MonetizationEntitlementState {
        .unknown
    }

    func waitUntilStarted() async {
        guard restoreCount == 0 else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func complete(with state: MonetizationEntitlementState) {
        completion?.resume(returning: state)
        completion = nil
    }
}

@MainActor
private final class IdentitySwitchingRestoreProvider: PurchaseRestoring {
    let isRevenueCatConfigured = true
    var identityGeneration: MonetizationIdentityTransition?
    private(set) var capturedIdentities: [MonetizationIdentityTransition] = []

    private var completions: [
        MonetizationIdentityTransition: CheckedContinuation<MonetizationEntitlementState, Never>
    ] = [:]
    private var callCountObservers: [CheckedContinuation<Void, Never>] = []

    init(identity: MonetizationIdentityTransition) {
        identityGeneration = identity
    }

    func restorePurchases(
        for identity: MonetizationIdentityTransition
    ) async -> MonetizationEntitlementState {
        capturedIdentities.append(identity)
        callCountObservers.forEach { $0.resume() }
        callCountObservers = []
        return await withCheckedContinuation { completions[identity] = $0 }
    }

    func restorePurchases() async -> MonetizationEntitlementState {
        .unknown
    }

    func waitUntilCallCount(_ expected: Int) async {
        guard capturedIdentities.count < expected else { return }
        await withCheckedContinuation { callCountObservers.append($0) }
        if capturedIdentities.count < expected {
            await waitUntilCallCount(expected)
        }
    }

    func complete(
        identity: MonetizationIdentityTransition,
        with state: MonetizationEntitlementState
    ) {
        completions.removeValue(forKey: identity)?.resume(returning: state)
    }
}
