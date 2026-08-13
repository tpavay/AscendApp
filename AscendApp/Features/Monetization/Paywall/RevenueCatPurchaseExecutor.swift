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
    private let refreshEntitlementState: @MainActor () async -> MonetizationEntitlementRefresh

    init(
        telemetry: TelemetryManager = .shared,
        transactionContextStore: PaywallTransactionContextStore = .shared,
        entitlementID: String = MonetizationConfiguration.live.revenueCatEntitlementID,
        applySubscriptionStatus: @escaping @MainActor (Set<String>) -> Void,
        refreshEntitlementState: @escaping @MainActor () async -> MonetizationEntitlementRefresh
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
            ?? RevenueCatPurchaseAnalyticsContext(placement: nil, presentationID: nil)
        telemetry.track(
            PaywallAnalyticsEvent.revenueCatPurchaseStarted(
                productID: productID,
                context: context
            )
        )

        do {
            let response = try await operation()

            if response.userCancelled {
                telemetry.track(
                    PaywallAnalyticsEvent.revenueCatPurchaseCancelled(
                        productID: productID,
                        context: context
                    )
                )
                return .cancelled
            }

            // The refreshed RevenueCat entitlement state - the device answer, whose refresh also
            // triggers server reconciliation but is not itself server-derived - is the single
            // source the verdict and the terminal both read. The `CustomerInfo` the purchase call
            // returned is a pre-refresh snapshot, so consulting it too would let two sources
            // disagree about one purchase. A refresh that established nothing says so, and never
            // stands in for a current answer.
            switch await refreshEntitlementState() {
            case .refreshed(let state):
                return verdict(forRefreshedState: state, productID: productID, context: context)
            case .unavailable(let failure):
                return failVerifiedPurchase(
                    productID: productID,
                    errorType: RevenueCatAnalyticsErrorType(refreshFailure: failure),
                    context: context
                )
            }
        } catch {
            switch Self.purchaseFailure(for: error) {
            case .cancelled:
                telemetry.track(
                    PaywallAnalyticsEvent.revenueCatPurchaseCancelled(
                        productID: productID,
                        context: context
                    )
                )
                return .cancelled
            case .pending:
                telemetry.track(
                    PaywallAnalyticsEvent.revenueCatPurchasePending(
                        productID: productID,
                        context: context
                    )
                )
                return .pending
            case .failed(let errorType):
                telemetry.track(
                    PaywallAnalyticsEvent.revenueCatPurchaseFailed(
                        productID: productID,
                        errorType: errorType,
                        attribution: .purchaseStarted(context)
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
                errorType: errorType,
                attribution: .unavailableBeforeRevenueCatCall
            )
        )
        return .failed(error)
    }

    private func verdict(
        forRefreshedState state: MonetizationEntitlementState,
        productID: String,
        context: RevenueCatPurchaseAnalyticsContext
    ) -> PurchaseResult {
        switch state {
        case .active(let entitlementIDs) where entitlementIDs.contains(entitlementID):
            applySubscriptionStatus(entitlementIDs)
            telemetry.track(
                PaywallAnalyticsEvent.revenueCatPurchaseCompleted(
                    productID: productID,
                    entitlementID: entitlementID,
                    context: context
                )
            )
            return .purchased

        case .active(let entitlementIDs):
            applySubscriptionStatus(entitlementIDs)
            return failVerifiedPurchase(
                productID: productID,
                errorType: .noActiveEntitlement,
                context: context
            )

        case .inactive:
            applySubscriptionStatus([])
            return failVerifiedPurchase(
                productID: productID,
                errorType: .noActiveEntitlement,
                context: context
            )

        case .unknown:
            // An unresolved answer is not evidence of a lapse, so the published status is left
            // alone - but it is not verified access either, so it cannot report `completed`.
            return failVerifiedPurchase(
                productID: productID,
                errorType: .entitlementUnresolved,
                context: context
            )
        }
    }

    private func failVerifiedPurchase(
        productID: String,
        errorType: RevenueCatAnalyticsErrorType,
        context: RevenueCatPurchaseAnalyticsContext
    ) -> PurchaseResult {
        telemetry.track(
            PaywallAnalyticsEvent.revenueCatPurchaseFailed(
                productID: productID,
                errorType: errorType,
                attribution: .purchaseStarted(context)
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
