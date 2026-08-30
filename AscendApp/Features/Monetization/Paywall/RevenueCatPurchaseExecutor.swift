import Foundation
import RevenueCat
import SuperwallKit

@MainActor
final class RevenueCatPurchaseExecutor {
    struct Execution: Sendable {
        let result: PurchaseResult
        let analyticsContext: RevenueCatPurchaseAnalyticsContext
        let purchaseIdentity: MonetizationIdentityTransition?
    }

    struct PurchaseResponse: Equatable, Sendable {
        let userCancelled: Bool
        let entitlementState: MonetizationEntitlementState

        init(
            userCancelled: Bool,
            entitlementState: MonetizationEntitlementState = .unknown
        ) {
            self.userCancelled = userCancelled
            self.entitlementState = entitlementState
        }
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
    private let currentIdentityGeneration: @MainActor () -> MonetizationIdentityTransition?
    private let adoptEntitlementState: @MainActor (
        MonetizationEntitlementState,
        MonetizationIdentityTransition
    ) -> Bool

    init(
        telemetry: TelemetryManager = .shared,
        transactionContextStore: PaywallTransactionContextStore = .shared,
        entitlementID: String = MonetizationConfiguration.live.revenueCatEntitlementID,
        applySubscriptionStatus: @escaping @MainActor (Set<String>) -> Void,
        refreshEntitlementState: @escaping @MainActor () async -> MonetizationEntitlementRefresh,
        currentIdentityGeneration: @escaping @MainActor () -> MonetizationIdentityTransition? = {
            nil
        },
        adoptEntitlementState: @escaping @MainActor (
            MonetizationEntitlementState,
            MonetizationIdentityTransition
        ) -> Bool = { _, _ in false }
    ) {
        self.telemetry = telemetry
        self.transactionContextStore = transactionContextStore
        self.entitlementID = entitlementID
        self.applySubscriptionStatus = applySubscriptionStatus
        self.refreshEntitlementState = refreshEntitlementState
        self.currentIdentityGeneration = currentIdentityGeneration
        self.adoptEntitlementState = adoptEntitlementState
    }

    func executePurchase(
        productID: String,
        operation: @MainActor () async throws -> PurchaseResponse
    ) async -> PurchaseResult {
        await executePurchaseWithContext(productID: productID, operation: operation).result
    }

    func executePurchaseWithContext(
        productID: String,
        operation: @MainActor () async throws -> PurchaseResponse
    ) async -> Execution {
        let storedContext = transactionContextStore.takeContext(for: productID)
        let context = storedContext?.analytics
            ?? RevenueCatPurchaseAnalyticsContext(placement: nil, presentationID: nil)
        // A hosted/native CTA owns the attempt before RevenueCat is invoked. Falling back to the
        // current generation is only for call sites that did not carry presentation context.
        let purchaseIdentity = storedContext?.identity ?? currentIdentityGeneration()
        func finish(_ result: PurchaseResult) -> Execution {
            Execution(
                result: result,
                analyticsContext: context,
                purchaseIdentity: purchaseIdentity
            )
        }
        guard let purchaseIdentity,
              purchaseIdentity.userID != nil,
              currentIdentityGeneration() == purchaseIdentity else {
            return finish(failVerifiedPurchase(
                productID: productID,
                errorType: .entitlementUnresolved,
                context: context,
                purchaseIdentity: purchaseIdentity
            ))
        }
        track(
            PaywallAnalyticsEvent.revenueCatPurchaseStarted(
                productID: productID,
                context: context
            ),
            for: purchaseIdentity
        )
        func terminalContext(
            _ providerOutcome: String,
            entitlementActive: Bool?
        ) -> RevenueCatPurchaseAnalyticsContext {
            context.terminal(
                providerOutcome: providerOutcome,
                identityMatches: currentIdentityGeneration() == purchaseIdentity,
                entitlementActive: entitlementActive
            )
        }

        do {
            let response = try await operation()

            if response.userCancelled {
                track(
                    PaywallAnalyticsEvent.revenueCatPurchaseCancelled(
                        productID: productID,
                        context: terminalContext("cancelled", entitlementActive: nil)
                    ),
                    for: purchaseIdentity
                )
                return finish(.cancelled)
            }

            guard currentIdentityGeneration() == purchaseIdentity,
                  adoptEntitlementState(response.entitlementState, purchaseIdentity) else {
                return finish(failVerifiedPurchase(
                    productID: productID,
                    errorType: .entitlementUnresolved,
                    context: context,
                    purchaseIdentity: purchaseIdentity
                ))
            }

            if response.entitlementState.hasActiveEntitlement(entitlementID) {
                return finish(verdict(
                    forRefreshedState: response.entitlementState,
                    productID: productID,
                    context: context,
                    purchaseIdentity: purchaseIdentity
                ))
            }

            // RevenueCat can finish Apple's transaction before its entitlement projection reaches
            // the returned CustomerInfo. Only this propagation-delay path performs a bounded,
            // RevenueCat-only verification refresh. The user remains non-repurchasable meanwhile.
            switch await refreshEntitlementState() {
            case .refreshed(let state):
                if currentIdentityGeneration() != purchaseIdentity {
                    return finish(failVerifiedPurchase(
                        productID: productID,
                        errorType: .entitlementUnresolved,
                        context: context,
                        purchaseIdentity: purchaseIdentity
                    ))
                }
                return finish(
                    verdict(
                        forRefreshedState: state,
                        productID: productID,
                        context: context,
                        purchaseIdentity: purchaseIdentity
                    )
                )
            case .unavailable(let failure):
                return finish(failVerifiedPurchase(
                    productID: productID,
                    errorType: RevenueCatAnalyticsErrorType(refreshFailure: failure),
                    context: context,
                    purchaseIdentity: purchaseIdentity
                ))
            }
        } catch {
            switch Self.purchaseFailure(for: error) {
            case .cancelled:
                track(
                    PaywallAnalyticsEvent.revenueCatPurchaseCancelled(
                        productID: productID,
                        context: terminalContext("cancelled", entitlementActive: nil)
                    ),
                    for: purchaseIdentity
                )
                return finish(.cancelled)
            case .pending:
                track(
                    PaywallAnalyticsEvent.revenueCatPurchasePending(
                        productID: productID,
                        context: terminalContext("pending_approval", entitlementActive: nil)
                    ),
                    for: purchaseIdentity
                )
                return finish(.pending)
            case .failed(let errorType):
                track(
                    PaywallAnalyticsEvent.revenueCatPurchaseFailed(
                        productID: productID,
                        errorType: errorType,
                        attribution: .purchaseStarted(
                            terminalContext("provider_failure", entitlementActive: nil)
                        )
                    ),
                    for: purchaseIdentity
                )
                return finish(.failed(error))
            }
        }
    }

    func failPurchaseBeforeRevenueCatCall(
        productID: String,
        error: any Error,
        errorType: RevenueCatAnalyticsErrorType
    ) -> PurchaseResult {
        let storedContext = transactionContextStore.takeContext(for: productID)
        let context = storedContext?.analytics
        let identity = storedContext?.identity ?? currentIdentityGeneration()
        let attribution: RevenueCatPurchaseAttribution = context.map {
            .purchaseStarted(
                $0.terminal(
                    providerOutcome: "configuration_failure",
                    identityMatches: identity != nil,
                    entitlementActive: nil
                )
            )
        } ?? .unavailableBeforeRevenueCatCall
        track(
            PaywallAnalyticsEvent.revenueCatPurchaseFailed(
                productID: productID,
                errorType: errorType,
                attribution: attribution
            ),
            for: identity
        )
        return .failed(error)
    }

    private func verdict(
        forRefreshedState state: MonetizationEntitlementState,
        productID: String,
        context: RevenueCatPurchaseAnalyticsContext,
        purchaseIdentity: MonetizationIdentityTransition?
    ) -> PurchaseResult {
        switch state {
        case .active(let entitlementIDs) where entitlementIDs.contains(entitlementID):
            applySubscriptionStatus(entitlementIDs)
            track(
                PaywallAnalyticsEvent.revenueCatPurchaseCompleted(
                    productID: productID,
                    entitlementID: entitlementID,
                    context: context.terminal(
                        providerOutcome: "purchased",
                        identityMatches: purchaseIdentity.map {
                            currentIdentityGeneration() == $0
                        } ?? false,
                        entitlementActive: true
                    )
                ),
                for: purchaseIdentity
            )
            return .purchased

        case .active(let entitlementIDs):
            applySubscriptionStatus(entitlementIDs)
            return failVerifiedPurchase(
                productID: productID,
                errorType: .noActiveEntitlement,
                context: context,
                purchaseIdentity: purchaseIdentity,
                entitlementActive: false
            )

        case .inactive:
            applySubscriptionStatus([])
            return failVerifiedPurchase(
                productID: productID,
                errorType: .noActiveEntitlement,
                context: context,
                purchaseIdentity: purchaseIdentity,
                entitlementActive: false
            )

        case .unknown:
            // An unresolved answer is not evidence of a lapse, so the published status is left
            // alone - but it is not verified access either, so it cannot report `completed`.
            return failVerifiedPurchase(
                productID: productID,
                errorType: .entitlementUnresolved,
                context: context,
                purchaseIdentity: purchaseIdentity
            )
        }
    }

    private func failVerifiedPurchase(
        productID: String,
        errorType: RevenueCatAnalyticsErrorType,
        context: RevenueCatPurchaseAnalyticsContext,
        purchaseIdentity: MonetizationIdentityTransition?,
        entitlementActive: Bool? = nil
    ) -> PurchaseResult {
        track(
            PaywallAnalyticsEvent.revenueCatPurchaseFailed(
                productID: productID,
                errorType: errorType,
                attribution: .purchaseStarted(
                    context.terminal(
                        providerOutcome: errorType == .noActiveEntitlement
                            ? "no_entitlement"
                            : "verification_unavailable",
                        identityMatches: purchaseIdentity.map {
                            currentIdentityGeneration() == $0
                        } ?? false,
                        entitlementActive: entitlementActive
                    )
                )
            ),
            for: purchaseIdentity
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

    private func track(
        _ event: PaywallAnalyticsEvent,
        for identity: MonetizationIdentityTransition?
    ) {
        guard let userID = identity?.userID else { return }
        telemetry.track(event, ifIdentifiedAs: userID)
    }
}
