import Foundation
import SuperwallKit
import Testing
@testable import AscendApp

/// The Superwall paywall's Restore button is one of the two restore surfaces the server
/// reconciliation contract names. It used to call the RevenueCat entitlement service directly and
/// skip reconciliation entirely, so these tests pin it to the shared coordinator.
@MainActor
struct RevenueCatPurchaseControllerRestoreTests {
    @Test
    func theSuperwallRestoreRoutesThroughTheSharedCoordinator() async {
        let coordinator = PaywallPurchaseCoordinatorSpy(
            restoredState: .active(["app_access"])
        )
        var published: [SuperwallKit.SubscriptionStatus] = []
        let controller = RevenueCatPurchaseController(
            coordinator: { coordinator },
            applySuperwallStatus: { published.append($0) },
            restoreService: restoreService(for: coordinator)
        )

        let result = await controller.restorePurchases()

        #expect(coordinator.restoreCount == 1)
        #expect(isRestored(result))
        #expect(published.count == 1)
    }

    @Test
    func aRestoreDuringAPendingIdentityTransitionIsRefused() async {
        let coordinator = PaywallPurchaseCoordinatorSpy(
            restoredState: .active(["app_access"])
        )
        coordinator.entitlementState = .unknown
        coordinator.identityGeneration = nil
        var published: [SuperwallKit.SubscriptionStatus] = []
        let controller = RevenueCatPurchaseController(
            coordinator: { coordinator },
            applySuperwallStatus: { published.append($0) },
            restoreService: restoreService(for: coordinator)
        )

        let result = await controller.restorePurchases()

        #expect(!isRestored(result))
        #expect(coordinator.restoreCount == 0)
        #expect(published.isEmpty)
    }

    @Test
    func aFailedSuperwallRestoreReportsTheFailure() async {
        let coordinator = PaywallPurchaseCoordinatorSpy(restoredState: .inactive)
        coordinator.restoreError = RestoreFailure()
        let controller = RevenueCatPurchaseController(
            coordinator: { coordinator },
            applySuperwallStatus: { _ in },
            restoreService: restoreService(for: coordinator)
        )

        let result = await controller.restorePurchases()

        #expect(coordinator.restoreCount == 1)
        #expect(!isRestored(result))
    }

    @Test
    func anUnconfiguredBuildNeverClaimsARestore() async {
        let coordinator = PaywallPurchaseCoordinatorSpy(restoredState: .unknown)
        coordinator.isRevenueCatConfigured = false
        let controller = RevenueCatPurchaseController(
            coordinator: { coordinator },
            applySuperwallStatus: { _ in },
            restoreService: restoreService(for: coordinator)
        )

        let result = await controller.restorePurchases()

        #expect(coordinator.restoreCount == 0)
        #expect(!isRestored(result))
    }

    /// `MonetizationManager.restorePurchases()` already forces server reconciliation, so a second
    /// forced refresh here would bill two Cloud Function round trips to one restore spinner.
    @Test
    func aRestoreReconcilesOnceInsteadOfRefreshingASecondTime() async {
        let coordinator = PaywallPurchaseCoordinatorSpy(
            restoredState: .active(["app_access"])
        )
        let controller = RevenueCatPurchaseController(
            coordinator: { coordinator },
            applySuperwallStatus: { _ in },
            restoreService: restoreService(for: coordinator)
        )

        _ = await controller.restorePurchases()

        #expect(coordinator.restoreCount == 1)
        #expect(coordinator.forcedRefreshCount == 0)
    }

    @Test
    func anUnresolvedRestoreLeavesTheSuperwallStatusAlone() async {
        let coordinator = PaywallPurchaseCoordinatorSpy(restoredState: .unknown)
        var published: [SuperwallKit.SubscriptionStatus] = []
        let controller = RevenueCatPurchaseController(
            coordinator: { coordinator },
            applySuperwallStatus: { published.append($0) },
            restoreService: restoreService(for: coordinator)
        )

        _ = await controller.restorePurchases()

        #expect(published.isEmpty)
    }

    private func isRestored(_ result: RestorationResult) -> Bool {
        if case .restored = result {
            return true
        }

        return false
    }

    private func isActive(_ status: SuperwallKit.SubscriptionStatus?) -> Bool {
        if case .active = status {
            return true
        }

        return false
    }

    private func restoreService(
        for coordinator: PaywallPurchaseCoordinatorSpy
    ) -> AppAccessRestoreService {
        AppAccessRestoreService(
            telemetry: makeTestTelemetry(
                sink: InMemoryTelemetrySink(destination: .analytics)
            ),
            entitlementID: "app_access",
            restorer: { coordinator }
        )
    }
}

private struct RestoreFailure: Error { }

@MainActor
private final class PaywallPurchaseCoordinatorSpy: PaywallPurchaseCoordinating {
    var isRevenueCatConfigured = true
    var entitlementState: MonetizationEntitlementState = .unknown
    var identityGeneration: MonetizationIdentityTransition? = MonetizationIdentityTransition(
        revision: 1,
        userID: "restore-test-user"
    )
    var restoreError: (any Error)?
    private(set) var restoreCount = 0
    private(set) var forcedRefreshCount = 0
    private let restoredState: MonetizationEntitlementState

    init(restoredState: MonetizationEntitlementState) {
        self.restoredState = restoredState
        entitlementState = restoredState
    }

    @discardableResult
    func refreshEntitlements(
        force: Bool,
        waitsForPendingIdentity: Bool
    ) async -> MonetizationEntitlementRefresh {
        if force {
            forcedRefreshCount += 1
        }

        return .refreshed(entitlementState)
    }

    @discardableResult
    func restorePurchases() async throws -> MonetizationEntitlementState {
        restoreCount += 1
        if let restoreError {
            throw restoreError
        }

        return restoredState
    }
}
