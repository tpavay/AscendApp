import Foundation
@preconcurrency import SuperwallKit

struct PaywallAnalyticsContext: Sendable, Hashable {
    let placement: String
    let paywallIdentifier: String
    let paywallName: String
    let presentedBy: String
    let isFreeTrialAvailable: Bool
    let presentationID: String?
    let presentationSourceType: String?
    let primaryProductID: String?
    let dismissReason: String?

    init(paywallInfo: PaywallInfo) {
        self.placement = paywallInfo.analyticsPlacement
        self.paywallIdentifier = paywallInfo.identifier
        self.paywallName = paywallInfo.name
        self.presentedBy = paywallInfo.presentedBy
        self.isFreeTrialAvailable = paywallInfo.isFreeTrialAvailable
        self.presentationID = paywallInfo.presentationId?.nilIfBlank
        self.presentationSourceType = paywallInfo.presentationSourceType?.nilIfBlank
        self.primaryProductID = paywallInfo.productIds.first?.nilIfBlank
        self.dismissReason = String(describing: paywallInfo.closeReason).nilIfBlank
    }

    var parameters: [String: TelemetryValue] {
        var parameters: [String: TelemetryValue] = [
            "placement": .string(placement),
            "paywall_identifier": .string(paywallIdentifier),
            "paywall_name": .string(paywallName),
            "presented_by": .string(presentedBy),
            "is_free_trial_available": .bool(isFreeTrialAvailable)
        ]

        if let presentationID {
            parameters["presentation_id"] = .string(presentationID)
        }

        if let presentationSourceType {
            parameters["presentation_source_type"] = .string(presentationSourceType)
        }

        if let primaryProductID {
            parameters["primary_product_id"] = .string(primaryProductID)
        }

        return parameters
    }
}

enum PaywallAnalyticsEvent: TelemetryEvent {
    case shown(context: PaywallAnalyticsContext)
    case dismissed(context: PaywallAnalyticsContext)
    case transactionStarted(context: PaywallAnalyticsContext, productID: String)
    case transactionCompleted(context: PaywallAnalyticsContext, productID: String, transactionType: String)
    case transactionFailed(context: PaywallAnalyticsContext, errorType: String, productID: String?)
    case transactionAbandoned(context: PaywallAnalyticsContext, productID: String)
    case restoreCompleted(context: PaywallAnalyticsContext, restoreType: String)
    case revenueCatPurchaseStarted(productID: String, context: RevenueCatPurchaseAnalyticsContext)
    case revenueCatPurchaseCompleted(
        productID: String,
        entitlementID: String,
        context: RevenueCatPurchaseAnalyticsContext
    )
    case revenueCatPurchaseCancelled(productID: String, context: RevenueCatPurchaseAnalyticsContext)
    case revenueCatPurchasePending(productID: String, context: RevenueCatPurchaseAnalyticsContext)
    case revenueCatPurchaseFailed(
        productID: String,
        errorType: RevenueCatAnalyticsErrorType,
        attribution: RevenueCatPurchaseAttribution
    )
    case revenueCatRestoreStarted
    case revenueCatRestoreCompleted(entitlementID: String)
    case revenueCatRestoreNotFound(entitlementID: String)
    case revenueCatRestoreFailed(
        entitlementID: String,
        errorType: RevenueCatAnalyticsErrorType
    )

    var record: TelemetryRecord {
        switch self {
        case .shown(let context):
            return TelemetryRecord(
                name: "paywall_shown",
                parameters: context.parameters
            )

        case .dismissed(let context):
            var parameters = context.parameters
            if let dismissReason = context.dismissReason {
                parameters["dismiss_reason"] = .string(dismissReason)
            }
            return TelemetryRecord(
                name: "paywall_dismissed",
                parameters: parameters
            )

        case .transactionStarted(let context, let productID):
            var parameters = context.parameters
            parameters["product_id"] = .string(productID)
            return TelemetryRecord(
                name: "paywall_transaction_started",
                parameters: parameters
            )

        case .transactionCompleted(let context, let productID, let transactionType):
            var parameters = context.parameters
            parameters["product_id"] = .string(productID)
            parameters["transaction_type"] = .string(transactionType)
            return TelemetryRecord(
                name: "paywall_transaction_completed",
                parameters: parameters
            )

        case .transactionFailed(let context, let errorType, let productID):
            var parameters = context.parameters
            parameters["error_type"] = .string(errorType)
            if let productID {
                parameters["product_id"] = .string(productID)
            }
            return TelemetryRecord(
                name: "paywall_transaction_failed",
                parameters: parameters
            )

        case .transactionAbandoned(let context, let productID):
            var parameters = context.parameters
            parameters["product_id"] = .string(productID)
            return TelemetryRecord(
                name: "paywall_transaction_abandoned",
                parameters: parameters
            )

        case .restoreCompleted(let context, let restoreType):
            var parameters = context.parameters
            parameters["restore_type"] = .string(restoreType)
            return TelemetryRecord(
                name: "paywall_restore_completed",
                parameters: parameters
            )

        case .revenueCatPurchaseStarted(let productID, let context):
            var parameters = context.parameters
            parameters["product_id"] = .string(productID)
            return TelemetryRecord(
                name: "revenuecat_purchase_started",
                parameters: parameters
            )

        case .revenueCatPurchaseCompleted(let productID, let entitlementID, let context):
            var parameters = context.parameters
            parameters["product_id"] = .string(productID)
            parameters["outcome"] = .string("success")
            parameters["entitlement_id"] = .string(entitlementID)
            parameters["entitlement_active"] = .bool(true)
            return TelemetryRecord(
                name: "revenuecat_purchase_completed",
                parameters: parameters
            )

        case .revenueCatPurchaseCancelled(let productID, let context):
            var parameters = context.parameters
            parameters["product_id"] = .string(productID)
            parameters["outcome"] = .string("user_cancelled")
            return TelemetryRecord(
                name: "revenuecat_purchase_cancelled",
                parameters: parameters
            )

        case .revenueCatPurchasePending(let productID, let context):
            var parameters = context.parameters
            parameters["product_id"] = .string(productID)
            parameters["outcome"] = .string("pending")
            return TelemetryRecord(
                name: "revenuecat_purchase_pending",
                parameters: parameters
            )

        case .revenueCatPurchaseFailed(let productID, let errorType, let attribution):
            var parameters = attribution.parameters
            parameters["product_id"] = .string(productID)
            parameters["outcome"] = .string("failed")
            parameters["error_type"] = .string(errorType.rawValue)
            return TelemetryRecord(
                name: "revenuecat_purchase_failed",
                parameters: parameters
            )

        case .revenueCatRestoreStarted:
            return TelemetryRecord(name: "revenuecat_restore_started")

        case .revenueCatRestoreCompleted(let entitlementID):
            return TelemetryRecord(
                name: "revenuecat_restore_completed",
                parameters: [
                    "outcome": .string("success"),
                    "entitlement_id": .string(entitlementID),
                    "entitlement_active": .bool(true)
                ]
            )

        case .revenueCatRestoreNotFound(let entitlementID):
            return TelemetryRecord(
                name: "revenuecat_restore_not_found",
                parameters: [
                    "outcome": .string("no_entitlement"),
                    "entitlement_id": .string(entitlementID),
                    "entitlement_active": .bool(false)
                ]
            )

        // A restore that never resolved an entitlement answer carries no `entitlement_active`:
        // reporting `false` would count an outage as evidence the climber holds nothing.
        case .revenueCatRestoreFailed(let entitlementID, let errorType):
            return TelemetryRecord(
                name: "revenuecat_restore_failed",
                parameters: [
                    "outcome": .string("failed"),
                    "entitlement_id": .string(entitlementID),
                    "error_type": .string(errorType.rawValue)
                ]
            )
        }
    }
}

extension PaywallInfo {
    var analyticsPlacement: String {
        if let placement = presentedByPlacementWithName?.nilIfBlank {
            return placement
        }

        return identifier
    }
}

extension TransactionError {
    var analyticsType: String {
        switch self {
        case .pending:
            return "pending"
        case .failure:
            return "failure"
        }
    }

    var analyticsProductID: String? {
        switch self {
        case .pending:
            return nil
        case .failure(_, let product):
            return product.productIdentifier
        }
    }
}

extension RestoreType {
    var analyticsType: String {
        switch self {
        case .viaPurchase:
            return "via_purchase"
        case .viaRestore:
            return "via_restore"
        }
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
