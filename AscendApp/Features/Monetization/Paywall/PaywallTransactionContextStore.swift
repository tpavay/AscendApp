import Foundation

@MainActor
final class PaywallTransactionContextStore {
    struct Context: Equatable, Sendable {
        let placement: String
        let presentationID: String?
    }

    static let shared = PaywallTransactionContextStore()

    private var contextsByProductID: [String: Context] = [:]

    func record(
        placement: String,
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
