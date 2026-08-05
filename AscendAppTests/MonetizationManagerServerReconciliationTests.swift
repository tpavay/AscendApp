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
