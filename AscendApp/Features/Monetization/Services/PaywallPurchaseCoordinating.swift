import Foundation

/// The one route a paywall purchase or restore takes back into monetization state.
///
/// Superwall's purchase controller used to call the RevenueCat entitlement service directly, which
/// meant its Restore button skipped the server reconciliation the account-settings Restore ran. A
/// single coordinator keeps the two restore surfaces from drifting apart again.
@MainActor
protocol PaywallPurchaseCoordinating: PurchaseRestoring {
    /// - Returns: The reconciled entitlement state the refresh resolved. A purchase verdict reads
    ///   this and nothing else, so the terminal it reports and the access the app grants can never
    ///   come from two disagreeing snapshots.
    @discardableResult
    func refreshEntitlements(force: Bool) async -> MonetizationEntitlementState
}

extension MonetizationManager: PaywallPurchaseCoordinating { }
