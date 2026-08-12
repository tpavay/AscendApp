import Foundation

@MainActor
final class PaywallTransactionContextStore {
    typealias Context = RevenueCatPurchaseAnalyticsContext

    static let shared = PaywallTransactionContextStore()

    private var contextsByProductID: [String: Context] = [:]

    func record(
        placement: SuperwallPlacement?,
        presentationID: String?,
        productID: String
    ) {
        contextsByProductID[productID] = Context(
            placement: placement,
            presentationID: presentationID
        )
    }

    func takeContext(for productID: String) -> Context? {
        contextsByProductID.removeValue(forKey: productID)
    }
}
