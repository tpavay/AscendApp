import Foundation

/// The one route a paywall purchase or restore takes back into monetization state.
///
/// Superwall's purchase controller used to call the RevenueCat entitlement service directly, which
/// meant its Restore button skipped the server reconciliation the account-settings Restore ran. A
/// single coordinator keeps the two restore surfaces from drifting apart again.
@MainActor
protocol PaywallPurchaseCoordinating: AnyObject {
    var isRevenueCatConfigured: Bool { get }

    func refreshEntitlements(force: Bool) async
    /// - Returns: What RevenueCat resolved for this restore. The controller publishes that rather
    ///   than the stored `entitlementState`, which a pending identity transition can hold at
    ///   `.unknown` even though the restore itself succeeded.
    @discardableResult
    func restorePurchases() async throws -> MonetizationEntitlementState
}

extension MonetizationManager: PaywallPurchaseCoordinating { }
