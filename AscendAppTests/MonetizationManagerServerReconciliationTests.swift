import Foundation
import Testing
@testable import AscendApp

@MainActor
struct MonetizationManagerServerReconciliationTests {
    @Test
    func purchaseAdoptionPublishesAndReconcilesOnlyForTheExactIdentityRevision() async throws {
        let service = EntitlementServiceStub(entitlementState: .inactive)
        let presenter = PaywallPresenterSpy()
        let reconciler = AppAccessReconcilerSpy()
        let configuration = MonetizationConfiguration(infoDictionary: [
            MonetizationConfiguration.revenueCatAPIKeyInfoKey: "appl_test",
            MonetizationConfiguration.superwallAPIKeyInfoKey: "pk_test",
            MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "NO"
        ])
        let manager = MonetizationManager(
            configuration: configuration,
            entitlementService: service,
            paywallPresenter: presenter,
            appAccessReconciler: reconciler
        )
        manager.configure(configuration: configuration)
        let exact = try #require(service.identityGeneration)
        let baselineStatuses = presenter.subscriptionStatuses.count

        #expect(manager.adoptPurchaseEntitlementState(.active(["app_access"]), for: exact))
        await reconciler.waitForCallCount(1)
        #expect(manager.hasAppAccess)
        #expect(presenter.subscriptionStatuses.count == baselineStatuses + 1)
        #expect(presenter.subscriptionStatuses.last == ["app_access"])
        #expect(reconciler.forcedCalls == [true])

        let staleSameUser = MonetizationIdentityTransition(
            revision: exact.revision &- 1,
            userID: exact.userID
        )
        let differentUser = MonetizationIdentityTransition(
            revision: exact.revision,
            userID: "different-user"
        )
        #expect(!manager.adoptPurchaseEntitlementState(.inactive, for: staleSameUser))
        #expect(!manager.adoptPurchaseEntitlementState(.inactive, for: differentUser))
        await Task.yield()
        #expect(manager.hasAppAccess)
        #expect(presenter.subscriptionStatuses.count == baselineStatuses + 1)
        #expect(reconciler.forcedCalls == [true])
    }

    @Test
    func refreshingWithAnActiveEntitlementAsksTheServerToReconcile() async {
        let reconciler = AppAccessReconcilerSpy()
        let manager = makeManager(
            entitlementState: .active(["app_access"]),
            reconciler: reconciler
        )

        await manager.refreshEntitlements()
        await reconciler.waitForCallCount(1)

        #expect(reconciler.forcedCalls == [false])
    }

    @Test
    func refreshingWithoutAnEntitlementNeverReachesTheServer() async {
        let reconciler = AppAccessReconcilerSpy()
        let manager = makeManager(entitlementState: .inactive, reconciler: reconciler)

        await manager.refreshEntitlements()

        #expect(reconciler.forcedCalls.isEmpty)
    }

    @Test
    func anUnknownEntitlementStateNeverReachesTheServer() async {
        let reconciler = AppAccessReconcilerSpy()
        let manager = makeManager(entitlementState: .unknown, reconciler: reconciler)

        await manager.refreshEntitlements()

        #expect(reconciler.forcedCalls.isEmpty)
    }

    @Test
    func restoringForcesServerReconciliationSoRestoreRestoresBackendAccess() async throws {
        let reconciler = AppAccessReconcilerSpy()
        let manager = makeManager(
            entitlementState: .active(["app_access"]),
            reconciler: reconciler
        )

        try await manager.restorePurchases()
        await reconciler.waitForCallCount(1)

        #expect(reconciler.forcedCalls == [true])
    }

    @Test
    func aFailedRestoreDoesNotClaimServerAccess() async {
        let reconciler = AppAccessReconcilerSpy()
        let manager = makeManager(
            entitlementState: .active(["app_access"]),
            restoreError: RestoreFailure(),
            reconciler: reconciler
        )

        await #expect(throws: RestoreFailure.self) {
            try await manager.restorePurchases()
        }
        #expect(reconciler.forcedCalls.isEmpty)
    }

    /// A pending identity transition has no settled owner, so restore must not adopt or reconcile
    /// an answer that could belong to the account being replaced.
    @Test
    func aRestoreDuringAPendingIdentityTransitionIsRefused() async throws {
        let reconciler = AppAccessReconcilerSpy()
        let entitlementService = EntitlementServiceStub(entitlementState: .unknown)
        entitlementService.restoredState = .active(["app_access"])
        let manager = MonetizationManager(
            configuration: MonetizationConfiguration(
                infoDictionary: [
                    MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "NO"
                ]
            ),
            entitlementService: entitlementService,
            paywallPresenter: PaywallPresenterSpy(),
            appAccessReconciler: reconciler
        )

        let restored = try await manager.restorePurchases()

        #expect(restored == .unknown)
        #expect(reconciler.forcedCalls.isEmpty)
    }

    /// Firebase is repair work after the device verdict, so a server request that never returns
    /// cannot hold a verified RevenueCat subscriber behind the gate.
    @Test
    func aReconcileThatOutlastsTheBudgetCannotDelayOrDowngradeTheVerdict() async {
        let sleeper = ControlledBudgetSleeper()
        let reconciler = SuspendingAppAccessReconciler()
        let manager = MonetizationManager(
            configuration: MonetizationConfiguration(
                infoDictionary: [
                    MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "NO"
                ]
            ),
            entitlementService: EntitlementServiceStub(entitlementState: .active(["app_access"])),
            paywallPresenter: PaywallPresenterSpy(),
            appAccessReconciler: reconciler,
            verdictBudget: MonetizationVerdictBudget(total: .seconds(10), sleeper: sleeper.sleep)
        )

        let refresh = await manager.refreshEntitlements(force: true, waitsForPendingIdentity: true)
        await sleeper.waitUntilSleeping()
        await reconciler.waitUntilReconciling()

        #expect(refresh == .refreshed(.active(["app_access"])))
        #expect(sleeper.requestedTotals == [.seconds(10)])

        reconciler.finishReconciling()
    }

    /// Once the exact RevenueCat verdict has returned, an account switch can invalidate routing,
    /// but background Firebase repair cannot retroactively rewrite the transaction terminal.
    @Test
    func anIdentityChangeDuringReconciliationCannotRewriteTheReturnedVerdict() async {
        let reconciler = SuspendingAppAccessReconciler()
        let entitlementService = EntitlementServiceStub(entitlementState: .active(["app_access"]))
        let manager = MonetizationManager(
            configuration: MonetizationConfiguration(
                infoDictionary: [
                    MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "NO"
                ]
            ),
            entitlementService: entitlementService,
            paywallPresenter: PaywallPresenterSpy(),
            appAccessReconciler: reconciler
        )

        let refresh = await manager.refreshEntitlements(force: true, waitsForPendingIdentity: true)
        await reconciler.waitUntilReconciling()
        _ = entitlementService.prepareIdentity(.climber("switched-user"))
        reconciler.finishReconciling()

        #expect(refresh == .refreshed(.active(["app_access"])))
        #expect(manager.entitlementState == .unknown)
    }

    /// A verdict that lands inside the budget is reported as the refresh resolved it, and the
    /// reconcile still runs inside the same attempt.
    @Test
    func aVerdictInsideTheBudgetKeepsItsRefreshedAnswerAndStillReconciles() async {
        let sleeper = ControlledBudgetSleeper()
        let reconciler = AppAccessReconcilerSpy()
        let manager = MonetizationManager(
            configuration: MonetizationConfiguration(
                infoDictionary: [
                    MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "NO"
                ]
            ),
            entitlementService: EntitlementServiceStub(entitlementState: .active(["app_access"])),
            paywallPresenter: PaywallPresenterSpy(),
            appAccessReconciler: reconciler,
            verdictBudget: MonetizationVerdictBudget(total: .seconds(10), sleeper: sleeper.sleep)
        )

        let refresh = await manager.refreshEntitlements(
            force: true,
            waitsForPendingIdentity: true
        )
        await reconciler.waitForCallCount(1)

        #expect(refresh == .refreshed(.active(["app_access"])))
        #expect(reconciler.forcedCalls == [true])
    }

    /// The background pass never holds a climber behind a spinner, so it spends no budget at all.
    @Test
    func aBackgroundRefreshNeverStartsTheVerdictBudget() async {
        let sleeper = ControlledBudgetSleeper()
        let manager = MonetizationManager(
            configuration: MonetizationConfiguration(
                infoDictionary: [
                    MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "NO"
                ]
            ),
            entitlementService: EntitlementServiceStub(entitlementState: .active(["app_access"])),
            paywallPresenter: PaywallPresenterSpy(),
            appAccessReconciler: AppAccessReconcilerSpy(),
            verdictBudget: MonetizationVerdictBudget(total: .seconds(10), sleeper: sleeper.sleep)
        )

        _ = await manager.refreshEntitlements()

        #expect(sleeper.requestedTotals.isEmpty)
    }

    private func makeManager(
        entitlementState: MonetizationEntitlementState,
        restoreError: (any Error)? = nil,
        reconciler: AppAccessReconcilerSpy
    ) -> MonetizationManager {
        MonetizationManager(
            configuration: MonetizationConfiguration(
                infoDictionary: [
                    MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "NO"
                ]
            ),
            entitlementService: EntitlementServiceStub(
                entitlementState: entitlementState,
                restoreError: restoreError
            ),
            paywallPresenter: PaywallPresenterSpy(),
            appAccessReconciler: reconciler
        )
    }
}

private struct RestoreFailure: Error { }

@MainActor
private final class AppAccessReconcilerSpy: AppAccessReconciling {
    private(set) var forcedCalls: [Bool] = []
    private var callObservers: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func reconcileAppAccess(force: Bool) async {
        forcedCalls.append(force)
        let ready = callObservers.filter { forcedCalls.count >= $0.count }
        callObservers.removeAll { forcedCalls.count >= $0.count }
        ready.forEach { $0.continuation.resume() }
    }

    func waitForCallCount(_ count: Int) async {
        guard forcedCalls.count < count else { return }
        await withCheckedContinuation { continuation in
            callObservers.append((count, continuation))
        }
    }
}

/// Holds the server round trip open so a test can expire the budget while it is still in flight.
@MainActor
private final class SuspendingAppAccessReconciler: AppAccessReconciling {
    private var continuation: CheckedContinuation<Void, Never>?
    private var startObserver: CheckedContinuation<Void, Never>?
    private var isReconciling = false

    func reconcileAppAccess(force: Bool) async {
        isReconciling = true
        startObserver?.resume()
        startObserver = nil

        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilReconciling() async {
        guard !isReconciling else { return }

        await withCheckedContinuation { continuation in
            startObserver = continuation
        }
    }

    func finishReconciling() {
        continuation?.resume()
        continuation = nil
    }
}
