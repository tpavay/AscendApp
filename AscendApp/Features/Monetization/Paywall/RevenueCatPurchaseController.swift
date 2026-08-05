import Foundation
import RevenueCat
import StoreKit
import SuperwallKit

/// Every case here reaches a climber - Superwall renders `errorDescription` verbatim in its
/// purchase-failure alert, and Ascend's own restore surfaces render the matching copy - so the
/// diagnostic detail stays in telemetry's bounded `error_type` and never in the message.
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
            return "No purchases found to restore."
        }
    }
}

@MainActor
final class RevenueCatPurchaseController: PurchaseController {
    private let applySuperwallStatus: @MainActor (SuperwallKit.SubscriptionStatus) -> Void

    private var subscriptionStatusTask: Task<Void, Never>?
    private let executor: RevenueCatPurchaseExecutor
    private let restoreService: AppAccessRestoreService

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
        restoreService: AppAccessRestoreService? = nil
    ) {
        self.applySuperwallStatus = applySuperwallStatus
        self.executor = executor ?? RevenueCatPurchaseExecutor(
            applySubscriptionStatus: { entitlementIDs in
                applySuperwallStatus(Self.subscriptionStatus(for: entitlementIDs))
            },
            refreshEntitlementState: {
                await coordinator().refreshEntitlements(force: true)
            }
        )
        self.restoreService = restoreService ?? AppAccessRestoreService(
            restorer: { coordinator() }
        )
    }

    func syncSubscriptionStatus() {
        guard Purchases.isConfigured else { return }

        subscriptionStatusTask?.cancel()
        subscriptionStatusTask = Task { [weak self] in
            if let customerInfo = try? await Purchases.shared.customerInfo() {
                await MainActor.run {
                    self?.applySubscriptionStatus(from: customerInfo)
                }
            }

            for await customerInfo in Purchases.shared.customerInfoStream {
                await MainActor.run {
                    self?.applySubscriptionStatus(from: customerInfo)
                }
            }
        }
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

        let storeProduct = RevenueCat.StoreProduct(sk2Product: sk2Product)
        return await executor.executePurchase(productID: product.productIdentifier) {
            let result = try await Purchases.shared.purchase(product: storeProduct)
            return RevenueCatPurchaseExecutor.PurchaseResponse(
                userCancelled: result.userCancelled
            )
        }
    }

    func restorePurchases() async -> RestorationResult {
        switch await restoreService.restore() {
        case .restored(let entitlementIDs):
            applySuperwallStatus(Self.subscriptionStatus(for: entitlementIDs))
            return .restored
        case .notFound:
            // Superwall has no "nothing to restore" result, and `.restored` would claim access this
            // climber does not have, so the failure it does have carries the nothing-found reason.
            return .failed(RevenueCatPurchaseControllerError.noPurchasesFound)
        case .failed(let error):
            return .failed(error)
        }
    }

    private func applySubscriptionStatus(from customerInfo: RevenueCat.CustomerInfo) {
        let entitlementIDs = Set(customerInfo.entitlements.activeInCurrentEnvironment.keys)

        applySuperwallStatus(Self.subscriptionStatus(for: entitlementIDs))
    }

    private static func subscriptionStatus(for entitlementIDs: Set<String>)
        -> SuperwallKit.SubscriptionStatus {
        let entitlements = entitlementIDs.map { SuperwallKit.Entitlement(id: $0) }

        return entitlements.isEmpty ? .inactive : .active(Set(entitlements))
    }
}
