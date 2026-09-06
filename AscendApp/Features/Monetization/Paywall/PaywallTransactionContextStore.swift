import Foundation

@MainActor
final class PaywallTransactionContextStore {
    struct Context: Sendable {
        let analytics: RevenueCatPurchaseAnalyticsContext
        /// Delivery ownership only. This never becomes a telemetry parameter.
        let identity: MonetizationIdentityTransition?
    }

    static let shared = PaywallTransactionContextStore()

    private var contextsByProductID: [String: Context] = [:]

    func record(
        placement: String?,
        presentationID: String?,
        gateAttemptID: String? = nil,
        recoveryPath: AppAccessGateRecoveryPath? = nil,
        identity: MonetizationIdentityTransition? = nil,
        productID: String
    ) {
        contextsByProductID[productID] = Context(
            analytics: RevenueCatPurchaseAnalyticsContext(
                placement: placement,
                presentationID: presentationID,
                gateAttemptID: gateAttemptID,
                recoveryPath: recoveryPath
            ),
            identity: identity
        )
    }

    func takeContext(for productID: String) -> Context? {
        contextsByProductID.removeValue(forKey: productID)
    }
}
