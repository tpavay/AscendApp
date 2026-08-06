import Foundation
import Testing
@testable import AscendApp

@MainActor
struct MonetizationManagerServerReconciliationTests {
    @Test
    func refreshingWithAnActiveEntitlementAsksTheServerToReconcile() async {
        let reconciler = AppAccessReconcilerSpy()
        let manager = makeManager(
            entitlementState: .active(["app_access"]),
            reconciler: reconciler
        )

        await manager.refreshEntitlements()

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

    /// A pending identity transition holds `entitlementState` at `.unknown`, but the restore still
    /// resolved a real answer, and that answer is what must drive server reconciliation.
    @Test
    func aRestoreDuringAPendingIdentityTransitionStillReconciles() async throws {
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

        #expect(restored == .active(["app_access"]))
        #expect(reconciler.forcedCalls == [true])
    }

    /// The one budget spans the whole verdict chain, so a reconcile that outlasts it collapses the
    /// attempt rather than letting the spinner run past the deadline the refresh already respected.
    @Test
    func aReconcileThatOutlastsTheBudgetCollapsesTheWholeVerdict() async {
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

        let refresh = Task {
            await manager.refreshEntitlements(force: true, waitsForPendingIdentity: true)
        }
        await sleeper.waitUntilSleeping()
        await reconciler.waitUntilReconciling()
        sleeper.expireBudget()

        #expect(await refresh.value == .unavailable(.refreshTimedOut))
        #expect(sleeper.requestedTotals == [.seconds(10)])

        reconciler.finishReconciling()
    }

    /// The reconcile suspends, and an account switch landing inside it leaves the pre-reconcile
    /// answer describing an identity the app no longer holds. Returning it would emit
    /// `revenuecat_purchase_completed` while the gate grants nothing.
    @Test
    func anIdentityChangeDuringReconciliationRefusesThePreReconcileAnswer() async {
        let reconciler = SuspendingAppAccessReconciler()
        let entitlementService = EntitlementServiceStub(entitlementState: .active(["app_access"]))
        // The budget is held open rather than left on the wall clock. What the identity change
        // produces is the assertion; a parallel test run that starves this refresh past ten real
        // seconds would collapse it to `.refreshTimedOut` and prove nothing either way.
        let budget = ControlledBudgetSleeper()
        let manager = MonetizationManager(
            configuration: MonetizationConfiguration(
                infoDictionary: [
                    MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "NO"
                ]
            ),
            entitlementService: entitlementService,
            paywallPresenter: PaywallPresenterSpy(),
            appAccessReconciler: reconciler,
            verdictBudget: MonetizationVerdictBudget(sleeper: budget.sleep)
        )

        let refresh = Task {
            await manager.refreshEntitlements(force: true, waitsForPendingIdentity: true)
        }
        await reconciler.waitUntilReconciling()
        _ = entitlementService.prepareIdentity(userId: "switched-user")
        reconciler.finishReconciling()

        #expect(await refresh.value == .unavailable(.identityUnresolved))
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

    func reconcileAppAccess(force: Bool) async {
        forcedCalls.append(force)
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
