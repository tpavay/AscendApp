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
            entitlementState: .active(["app_access"])
        )
        var published: [SuperwallKit.SubscriptionStatus] = []
        let controller = RevenueCatPurchaseController(
            coordinator: { coordinator },
            applySuperwallStatus: { published.append($0) }
        )

        let result = await controller.restorePurchases()

        #expect(coordinator.restoreCount == 1)
        #expect(isRestored(result))
        #expect(published.count == 1)
    }

    @Test
    func aFailedSuperwallRestoreReportsTheFailure() async {
        let coordinator = PaywallPurchaseCoordinatorSpy(entitlementState: .inactive)
        coordinator.restoreError = RestoreFailure()
        let controller = RevenueCatPurchaseController(
            coordinator: { coordinator },
            applySuperwallStatus: { _ in }
        )

        let result = await controller.restorePurchases()

        #expect(coordinator.restoreCount == 1)
        #expect(!isRestored(result))
    }

    @Test
    func anUnconfiguredBuildNeverClaimsARestore() async {
        let coordinator = PaywallPurchaseCoordinatorSpy(entitlementState: .unknown)
        coordinator.isRevenueCatConfigured = false
        let controller = RevenueCatPurchaseController(
            coordinator: { coordinator },
            applySuperwallStatus: { _ in }
        )

        let result = await controller.restorePurchases()

        #expect(coordinator.restoreCount == 0)
        #expect(!isRestored(result))
    }

    @Test
    func anUnresolvedEntitlementLeavesTheSuperwallStatusAlone() async {
        let coordinator = PaywallPurchaseCoordinatorSpy(entitlementState: .unknown)
        var published: [SuperwallKit.SubscriptionStatus] = []
        let controller = RevenueCatPurchaseController(
            coordinator: { coordinator },
            applySuperwallStatus: { published.append($0) }
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
}

private struct RestoreFailure: Error { }

@MainActor
private final class PaywallPurchaseCoordinatorSpy: PaywallPurchaseCoordinating {
    var isRevenueCatConfigured = true
    var entitlementState: MonetizationEntitlementState
    var restoreError: (any Error)?
    private(set) var restoreCount = 0
    private(set) var forcedRefreshCount = 0

    init(entitlementState: MonetizationEntitlementState) {
        self.entitlementState = entitlementState
    }

    func refreshEntitlements(force: Bool) async {
        if force {
            forcedRefreshCount += 1
        }
    }

    func restorePurchases() async throws {
        restoreCount += 1
        if let restoreError {
            throw restoreError
        }
    }
}
