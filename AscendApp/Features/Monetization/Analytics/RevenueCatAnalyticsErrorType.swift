import Foundation

enum RevenueCatAnalyticsErrorType: String, Sendable {
    case configuration
    case missingStoreProduct = "missing_store_product"
    case network
    case noActiveEntitlement = "no_active_entitlement"
    case purchaseNotAllowed = "purchase_not_allowed"
    case receipt
    case store
    case unknown
}
