import Foundation

@MainActor
protocol PurchaseRestoring: AnyObject {
    var isRevenueCatConfigured: Bool { get }

    func restorePurchases() async throws
}

extension MonetizationManager: PurchaseRestoring { }
