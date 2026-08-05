import Foundation

@MainActor
protocol PurchaseRestoring: AnyObject {
    var isRevenueCatConfigured: Bool { get }

    @discardableResult
    func restorePurchases() async throws -> MonetizationEntitlementState
}

extension MonetizationManager: PurchaseRestoring { }
