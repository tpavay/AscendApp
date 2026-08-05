import Foundation

/// The one route a paywall purchase or restore takes back into monetization state.
///
/// Superwall's purchase controller used to call the RevenueCat entitlement service directly, which
/// meant its Restore button skipped the server reconciliation the account-settings Restore ran. A
/// single coordinator keeps the two restore surfaces from drifting apart again.
@MainActor
protocol PaywallPurchaseCoordinating: PurchaseRestoring {
    /// - Returns: Whether the refresh established a current RevenueCat answer, and what it was. A
    ///   purchase verdict reads this and nothing else, so the terminal it reports and the access the
    ///   app grants can never come from two disagreeing snapshots - and an unavailable refresh is
    ///   reported as such rather than as whatever the stored entitlement happened to be.
    @discardableResult
    func refreshEntitlements(
        force: Bool,
        waitsForPendingIdentity: Bool
    ) async -> MonetizationEntitlementRefresh
}

extension MonetizationManager: PaywallPurchaseCoordinating { }
