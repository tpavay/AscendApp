import Foundation
import RevenueCat
import StoreKit
import SuperwallKit

/// Copy a climber can be shown, so the diagnostic detail stays in telemetry's bounded `error_type`
/// and never in the message.
///
/// Superwall renders `errorDescription` verbatim in its purchase-failure alert, and Ascend's own
/// account-settings and app-access-gate restore surfaces render the matching copy. Superwall's
/// *restore*-failure alert is the exception: it presents `options.paywalls.restoreFailed` and
/// discards the error it was handed, so `noPurchasesFound` never reaches a climber on the paywall.
enum RevenueCatPurchaseControllerError: LocalizedError {
    case missingStoreKitProduct
    case monetizationUnavailable
    case entitlementUnconfirmed
    case noPurchasesFound

    var errorDescription: String? {
        switch self {
        case .missingStoreKitProduct:
            return "Ascend couldn't start that purchase. Try again in a moment."
        case .monetizationUnavailable:
            return "Ascend could not reach the App Store. Check your connection and try again."
        case .entitlementUnconfirmed:
            return "Ascend couldn't confirm your subscription. Check your connection and try again."
        case .noPurchasesFound:
            return "No active Ascend subscription was found for this Apple ID."
        }
    }
}

@MainActor
final class RevenueCatPurchaseController: PurchaseController {
    private let applySuperwallStatus: @MainActor (SuperwallKit.SubscriptionStatus) -> Void

    private let executor: RevenueCatPurchaseExecutor
    private let restoreService: AppAccessRestoreService
    private let restoreAnalyticsContext: @MainActor () -> AppAccessRestoreAnalyticsContext
    private let isPurchasesConfigured: @MainActor () -> Bool
    private let recoveryRouter: @MainActor (
        HostedPurchaseRecovery,
        RevenueCatPurchaseAnalyticsContext,
        MonetizationIdentityTransition
    ) async -> Bool

    init(
        // Resolved on use, not at init: `MonetizationManager.shared` owns the Superwall presenter
        // that owns this controller, so reading it here would re-enter a running static initializer.
        coordinator: @escaping @MainActor () -> any PaywallPurchaseCoordinating = {
            MonetizationManager.shared
        },
        applySuperwallStatus: @escaping @MainActor (SuperwallKit.SubscriptionStatus) -> Void = {
            Superwall.shared.subscriptionStatus = $0
        },
        executor: RevenueCatPurchaseExecutor? = nil,
        restoreService: AppAccessRestoreService? = nil,
        restoreAnalyticsContext: @escaping @MainActor () -> AppAccessRestoreAnalyticsContext = {
            SuperwallPaywallPresenter.shared.makeHostedRestoreAnalyticsContext()
        },
        isPurchasesConfigured: @escaping @MainActor () -> Bool = {
            Purchases.isConfigured
        },
        recoveryRouter: @escaping @MainActor (
            HostedPurchaseRecovery,
            RevenueCatPurchaseAnalyticsContext,
            MonetizationIdentityTransition
        ) async -> Bool = { recovery, context, identity in
            await SuperwallPaywallPresenter.shared.recoverHostedPurchase(
                recovery,
                context: context,
                identity: identity
            )
        }
    ) {
        self.applySuperwallStatus = applySuperwallStatus
        self.executor = executor ?? RevenueCatPurchaseExecutor(
            applySubscriptionStatus: { entitlementIDs in
                applySuperwallStatus(Self.subscriptionStatus(for: entitlementIDs))
            },
            refreshEntitlementState: {
                // A purchase can land mid sign-in, and the climber is already waiting on the
                // transaction spinner, so this one refresh waits out an unresolved identity rather
                // than reporting the transitional answer as the verdict.
                await coordinator().refreshEntitlements(
                    force: true,
                    waitsForPendingIdentity: true
                )
            },
            currentIdentityGeneration: {
                coordinator().identityGeneration
            },
            adoptEntitlementState: { state, identity in
                coordinator().adoptPurchaseEntitlementState(state, for: identity)
            }
        )
        self.restoreService = restoreService ?? .shared
        self.restoreAnalyticsContext = restoreAnalyticsContext
        self.isPurchasesConfigured = isPurchasesConfigured
        self.recoveryRouter = recoveryRouter
    }

    func purchase(product: SuperwallKit.StoreProduct) async -> PurchaseResult {
        guard let sk2Product = product.sk2Product else {
            let error = RevenueCatPurchaseControllerError.missingStoreKitProduct
            return executor.failPurchaseBeforeRevenueCatCall(
                productID: product.productIdentifier,
                error: error,
                errorType: .missingStoreProduct
            )
        }

        guard isPurchasesConfigured() else {
            return executor.failPurchaseBeforeRevenueCatCall(
                productID: product.productIdentifier,
                error: RevenueCatPurchaseControllerError.monetizationUnavailable,
                errorType: .configuration
            )
        }

        let storeProduct = RevenueCat.StoreProduct(sk2Product: sk2Product)
        let execution = await executor.executePurchaseWithContext(
            productID: product.productIdentifier
        ) {
            let result = try await Purchases.shared.purchase(product: storeProduct)
            return RevenueCatPurchaseExecutor.PurchaseResponse(
                userCancelled: result.userCancelled,
                entitlementState: RevenueCatPurchasesProvider.entitlementState(
                    from: result.customerInfo
                )
            )
        }

        return await resolveHostedExecution(execution)
    }

    /// Resolves the app-owned hosted-paywall recovery before Superwall receives the transaction
    /// terminal. Pending and unconfirmed purchases must dismiss into Ascend's non-repurchase state
    /// first so Superwall cannot leave a reusable CTA or show the wrong generic alert.
    func resolveHostedExecution(
        _ execution: RevenueCatPurchaseExecutor.Execution
    ) async -> PurchaseResult {
        switch execution.result {
        case .pending:
            if let identity = execution.purchaseIdentity {
                _ = await recoveryRouter(
                    .pendingApproval,
                    execution.analyticsContext,
                    identity
                )
            }
        case .failed(let error):
            if let controllerError = error as? RevenueCatPurchaseControllerError,
               case .entitlementUnconfirmed = controllerError,
               let identity = execution.purchaseIdentity {
                _ = await recoveryRouter(
                    .verificationUnavailable,
                    execution.analyticsContext,
                    identity
                )
            }
        case .purchased, .cancelled:
            break
        @unknown default:
            break
        }
        return execution.result
    }

    func restorePurchases() async -> RestorationResult {
        switch await restoreService.restore(context: restoreAnalyticsContext()) {
        case .restored(let entitlementIDs):
            applySuperwallStatus(Self.subscriptionStatus(for: entitlementIDs))
            return .restored
        case .notFound:
            // Superwall has no "nothing to restore" result, and `.restored` would claim access this
            // climber does not have, so the failure it does have is the truthful answer. Superwall
            // shows its own restore-failed alert here; only telemetry and Ascend's own restore
            // surfaces carry the nothing-found reason.
            return .failed(RevenueCatPurchaseControllerError.noPurchasesFound)
        case .failed(let error):
            return .failed(error)
        }
    }

    static func subscriptionStatus(for entitlementIDs: Set<String>)
        -> SuperwallKit.SubscriptionStatus {
        let entitlements = entitlementIDs.map { SuperwallKit.Entitlement(id: $0) }

        return entitlements.isEmpty ? .inactive : .active(Set(entitlements))
    }
}
