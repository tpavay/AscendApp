import Foundation

@MainActor
protocol PurchaseRestoring: AnyObject {
    var isRevenueCatConfigured: Bool { get }
    var identityGeneration: MonetizationIdentityTransition? { get }

    /// - Returns: What RevenueCat resolved for this restore. Callers publish that rather than the
    ///   stored `entitlementState`, which a pending identity transition can hold at `.unknown` even
    ///   though the restore itself succeeded.
    @discardableResult
    func restorePurchases(
        for identity: MonetizationIdentityTransition
    ) async throws -> MonetizationEntitlementState
    @discardableResult
    func restorePurchases() async throws -> MonetizationEntitlementState
}

extension MonetizationManager: PurchaseRestoring { }

extension PurchaseRestoring {
    var identityGeneration: MonetizationIdentityTransition? { nil }

    func restorePurchases(
        for identity: MonetizationIdentityTransition
    ) async throws -> MonetizationEntitlementState {
        try await restorePurchases()
    }
}
