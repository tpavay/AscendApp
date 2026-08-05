import Foundation

/// The one route a paywall purchase or restore takes back into monetization state.
///
/// Superwall's purchase controller used to call the RevenueCat entitlement service directly, which
/// meant its Restore button skipped the server reconciliation the account-settings Restore ran. A
/// single coordinator keeps the two restore surfaces from drifting apart again.
@MainActor
protocol PaywallPurchaseCoordinating: AnyObject {
    var isRevenueCatConfigured: Bool { get }
    var entitlementState: MonetizationEntitlementState { get }

    func refreshEntitlements(force: Bool) async
    func restorePurchases() async throws
}

extension MonetizationManager: PaywallPurchaseCoordinating { }
