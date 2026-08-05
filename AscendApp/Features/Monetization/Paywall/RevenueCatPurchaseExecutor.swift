import Foundation
import RevenueCat
import SuperwallKit

@MainActor
final class RevenueCatPurchaseExecutor {
    struct PurchaseResponse: Equatable, Sendable {
        let userCancelled: Bool
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
    private let refreshEntitlementState: @MainActor () async -> MonetizationEntitlementState

    init(
        telemetry: TelemetryManager = .shared,
        transactionContextStore: PaywallTransactionContextStore = .shared,
        entitlementID: String = MonetizationConfiguration.live.revenueCatEntitlementID,
        applySubscriptionStatus: @escaping @MainActor (Set<String>) -> Void,
        refreshEntitlementState: @escaping @MainActor () async -> MonetizationEntitlementState
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

            // The refreshed, server-reconciled state is the single source the verdict and the
            // terminal both read. The `CustomerInfo` the purchase call returned is a pre-refresh
            // snapshot, so consulting it too would let two sources disagree about one purchase.
            return verdict(
                forRefreshedState: await refreshEntitlementState(),
                productID: productID
            )
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

    private func verdict(
        forRefreshedState state: MonetizationEntitlementState,
        productID: String
    ) -> PurchaseResult {
        switch state {
        case .active(let entitlementIDs) where entitlementIDs.contains(entitlementID):
            applySubscriptionStatus(entitlementIDs)
            telemetry.track(
                PaywallAnalyticsEvent.revenueCatPurchaseCompleted(
                    productID: productID,
                    entitlementID: entitlementID
                )
            )
            return .purchased

        case .active(let entitlementIDs):
            applySubscriptionStatus(entitlementIDs)
            return failVerifiedPurchase(productID: productID, errorType: .noActiveEntitlement)

        case .inactive:
            applySubscriptionStatus([])
            return failVerifiedPurchase(productID: productID, errorType: .noActiveEntitlement)

        case .unknown:
            // An unresolved answer is not evidence of a lapse, so the published status is left
            // alone - but it is not verified access either, so it cannot report `completed`.
            return failVerifiedPurchase(productID: productID, errorType: .entitlementUnresolved)
        }
    }

    private func failVerifiedPurchase(
        productID: String,
        errorType: RevenueCatAnalyticsErrorType
    ) -> PurchaseResult {
        telemetry.track(
            PaywallAnalyticsEvent.revenueCatPurchaseFailed(
                productID: productID,
                errorType: errorType
            )
        )
        return .failed(RevenueCatPurchaseControllerError.entitlementUnconfirmed)
    }

    private static func purchaseFailure(for error: any Error) -> PurchaseFailure {
        switch RevenueCatAnalyticsErrorType.revenueCatErrorCode(for: error) {
        case .purchaseCancelledError:
            return .cancelled
        case .paymentPendingError:
            return .pending
        default:
            return .failed(RevenueCatAnalyticsErrorType(error: error))
        }
    }
}
