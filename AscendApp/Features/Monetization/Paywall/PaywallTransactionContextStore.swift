import Foundation

@MainActor
final class PaywallTransactionContextStore {
    typealias Context = RevenueCatPurchaseAnalyticsContext

    static let shared = PaywallTransactionContextStore()

    private var contextsByProductID: [String: Context] = [:]

    func record(
        placement: String?,
        presentationID: String?,
        gateAttemptID: String? = nil,
        recoveryPath: AppAccessGateRecoveryPath? = nil,
        productID: String
    ) {
        contextsByProductID[productID] = Context(
            placement: placement,
            presentationID: presentationID,
            gateAttemptID: gateAttemptID,
            recoveryPath: recoveryPath
        )
    }

    func takeContext(for productID: String) -> Context? {
        contextsByProductID.removeValue(forKey: productID)
    }
}
