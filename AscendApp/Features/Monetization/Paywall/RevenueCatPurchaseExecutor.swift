import Foundation
import RevenueCat
import SuperwallKit

@MainActor
final class RevenueCatPurchaseExecutor {
    struct PurchaseResponse: Equatable, Sendable {
        let userCancelled: Bool
        let activeEntitlementIDs: Set<String>
    }

    private enum PurchaseFailure {
        case cancelled
        case failed(RevenueCatAnalyticsErrorType)
        case pending
    }

    private let telemetry: TelemetryManager
    private let transactionContextStore: PaywallTransactionContextStore
    private let entitlementID: String
    private let applySubscriptionStatus: @MainActor (Set<String>) -> Void
    private let refreshEntitlementState: @MainActor () async -> Void

    init(
        telemetry: TelemetryManager = .shared,
        transactionContextStore: PaywallTransactionContextStore = .shared,
        entitlementID: String = MonetizationConfiguration.live.revenueCatEntitlementID,
        applySubscriptionStatus: @escaping @MainActor (Set<String>) -> Void = { entitlementIDs in
            let entitlements = Set(entitlementIDs.map { SuperwallKit.Entitlement(id: $0) })
            Superwall.shared.subscriptionStatus = entitlements.isEmpty
                ? .inactive
                : .active(entitlements)
        },
        refreshEntitlementState: @escaping @MainActor () async -> Void = {
            await RevenueCatEntitlementService.shared.refreshCustomerInfo()
        }
    ) {
        self.telemetry = telemetry
        self.transactionContextStore = transactionContextStore
        self.entitlementID = entitlementID
        self.applySubscriptionStatus = applySubscriptionStatus
        self.refreshEntitlementState = refreshEntitlementState
    }

    func executePurchase(
        productID: String,
        operation: @MainActor () async throws -> PurchaseResponse
    ) async -> PurchaseResult {
        let context = transactionContextStore.takeContext(for: productID)
        telemetry.track(
            PaywallAnalyticsEvent.revenueCatPurchaseStarted(
                productID: productID,
                placement: context?.placement ?? "unknown",
                presentationID: context?.presentationID
            )
        )

        do {
            let response = try await operation()

            if response.userCancelled {
                telemetry.track(PaywallAnalyticsEvent.revenueCatPurchaseCancelled(productID: productID))
                return .cancelled
            }

            applySubscriptionStatus(response.activeEntitlementIDs)
            await refreshEntitlementState()

            guard response.activeEntitlementIDs.contains(entitlementID) else {
                telemetry.track(
                    PaywallAnalyticsEvent.revenueCatPurchaseFailed(
                        productID: productID,
                        errorType: .noActiveEntitlement
                    )
                )
                return .failed(RevenueCatPurchaseControllerError.noActiveEntitlement)
            }

            telemetry.track(
                PaywallAnalyticsEvent.revenueCatPurchaseCompleted(
                    productID: productID,
                    entitlementID: entitlementID
                )
            )
            return .purchased
        } catch {
            switch Self.purchaseFailure(for: error) {
            case .cancelled:
                telemetry.track(PaywallAnalyticsEvent.revenueCatPurchaseCancelled(productID: productID))
                return .cancelled
            case .pending:
                telemetry.track(PaywallAnalyticsEvent.revenueCatPurchasePending(productID: productID))
                return .pending
            case .failed(let errorType):
                telemetry.track(
                    PaywallAnalyticsEvent.revenueCatPurchaseFailed(
                        productID: productID,
                        errorType: errorType
                    )
                )
                return .failed(error)
            }
        }
    }

    func failPurchaseBeforeRevenueCatCall(
        productID: String,
        error: any Error,
        errorType: RevenueCatAnalyticsErrorType
    ) -> PurchaseResult {
        _ = transactionContextStore.takeContext(for: productID)
        telemetry.track(
            PaywallAnalyticsEvent.revenueCatPurchaseFailed(
                productID: productID,
                errorType: errorType
            )
        )
        return .failed(error)
    }

    func executeRestore(
        operation: @MainActor () async throws -> Set<String>
    ) async -> RestorationResult {
        telemetry.track(PaywallAnalyticsEvent.revenueCatRestoreStarted)

        do {
            let activeEntitlementIDs = try await operation()
            applySubscriptionStatus(activeEntitlementIDs)
            await refreshEntitlementState()

            guard activeEntitlementIDs.contains(entitlementID) else {
                telemetry.track(
                    PaywallAnalyticsEvent.revenueCatRestoreFailed(
                        outcome: .noEntitlement,
                        entitlementID: entitlementID,
                        errorType: .noActiveEntitlement
                    )
                )
                return .failed(RevenueCatPurchaseControllerError.noActiveEntitlement)
            }

            telemetry.track(
                PaywallAnalyticsEvent.revenueCatRestoreCompleted(entitlementID: entitlementID)
            )
            return .restored
        } catch {
            telemetry.track(
                PaywallAnalyticsEvent.revenueCatRestoreFailed(
                    outcome: .failed,
                    entitlementID: entitlementID,
                    errorType: Self.analyticsErrorType(for: error)
                )
            )
            return .failed(error)
        }
    }

    static func analyticsErrorType(for error: any Error) -> RevenueCatAnalyticsErrorType {
        guard let errorCode = revenueCatErrorCode(for: error) else {
            return .unknown
        }

        switch errorCode {
        case .networkError, .offlineConnectionError, .apiEndpointBlockedError,
             .productRequestTimedOut:
            return .network
        case .purchaseNotAllowedError, .ineligibleError, .insufficientPermissionsError:
            return .purchaseNotAllowed
        case .receiptAlreadyInUseError, .invalidReceiptError, .missingReceiptFileError,
             .receiptInUseByOtherSubscriberError, .purchaseBelongsToOtherUser:
            return .receipt
        case .invalidCredentialsError, .invalidAppleSubscriptionKeyError, .configurationError,
             .signatureVerificationFailed:
            return .configuration
        case .storeProblemError, .purchaseInvalidError, .productNotAvailableForPurchaseError,
             .productAlreadyPurchasedError, .operationAlreadyInProgressForProductError:
            return .store
        default:
            return .unknown
        }
    }

    private static func purchaseFailure(for error: any Error) -> PurchaseFailure {
        switch revenueCatErrorCode(for: error) {
        case .purchaseCancelledError:
            return .cancelled
        case .paymentPendingError:
            return .pending
        default:
            return .failed(analyticsErrorType(for: error))
        }
    }

    private static func revenueCatErrorCode(for error: any Error) -> ErrorCode? {
        if let errorCode = error as? ErrorCode {
            return errorCode
        }

        let nsError = error as NSError
        guard nsError.domain == ErrorCode.errorDomain else { return nil }
        return ErrorCode(rawValue: nsError.code)
    }
}
