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
