import Foundation

@MainActor
protocol PurchaseRestoring: AnyObject {
    var isRevenueCatConfigured: Bool { get }

    /// - Returns: What RevenueCat resolved for this restore. Callers publish that rather than the
    ///   stored `entitlementState`, which a pending identity transition can hold at `.unknown` even
    ///   though the restore itself succeeded.
    @discardableResult
    func restorePurchases() async throws -> MonetizationEntitlementState
}

extension MonetizationManager: PurchaseRestoring { }
