import Foundation
import RevenueCat

enum RevenueCatAnalyticsErrorType: String, Sendable {
    case configuration
    case entitlementUnresolved = "entitlement_unresolved"
    case missingStoreProduct = "missing_store_product"
    case network
    case noActiveEntitlement = "no_active_entitlement"
    case purchaseNotAllowed = "purchase_not_allowed"
    case receipt
    case store
    case unknown

    /// Buckets an arbitrary thrown error into the low-cardinality set the paywall funnel reports.
    init(error: any Error) {
        guard let errorCode = Self.revenueCatErrorCode(for: error) else {
            self = .unknown
            return
        }

        switch errorCode {
        case .networkError, .offlineConnectionError, .apiEndpointBlockedError,
             .productRequestTimedOut:
            self = .network
        case .purchaseNotAllowedError, .ineligibleError, .insufficientPermissionsError:
            self = .purchaseNotAllowed
        case .receiptAlreadyInUseError, .invalidReceiptError, .missingReceiptFileError,
             .receiptInUseByOtherSubscriberError, .purchaseBelongsToOtherUser:
            self = .receipt
        case .invalidCredentialsError, .invalidAppleSubscriptionKeyError, .configurationError,
             .signatureVerificationFailed:
            self = .configuration
        case .storeProblemError, .purchaseInvalidError, .productNotAvailableForPurchaseError,
             .productAlreadyPurchasedError, .operationAlreadyInProgressForProductError:
            self = .store
        default:
            self = .unknown
        }
    }

    static func revenueCatErrorCode(for error: any Error) -> ErrorCode? {
        if let errorCode = error as? ErrorCode {
            return errorCode
        }

        let nsError = error as NSError
        guard nsError.domain == ErrorCode.errorDomain else { return nil }
        return ErrorCode(rawValue: nsError.code)
    }
}
