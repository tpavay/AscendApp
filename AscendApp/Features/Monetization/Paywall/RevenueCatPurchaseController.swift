import Foundation
import RevenueCat
import StoreKit
import SuperwallKit

enum RevenueCatPurchaseControllerError: LocalizedError {
    case missingStoreKitProduct
    case monetizationUnavailable
    case noActiveEntitlement

    var errorDescription: String? {
        switch self {
        case .missingStoreKitProduct:
            return "Superwall did not provide a StoreKit 2 product for RevenueCat to purchase."
        case .monetizationUnavailable:
            return "Ascend could not reach the App Store. Check your connection and try again."
        case .noActiveEntitlement:
            return "RevenueCat did not confirm the app_access entitlement."
        }
    }
}

@MainActor
final class RevenueCatPurchaseController: PurchaseController {
    // Resolved on use, not at init: `MonetizationManager.shared` owns the Superwall presenter that
    // owns this controller, so reading it here would re-enter a static initializer still running.
    private let coordinator: @MainActor () -> any PaywallPurchaseCoordinating
    private let applySuperwallStatus: @MainActor (SuperwallKit.SubscriptionStatus) -> Void

    private var subscriptionStatusTask: Task<Void, Never>?
    private let executor: RevenueCatPurchaseExecutor

    init(
        coordinator: @escaping @MainActor () -> any PaywallPurchaseCoordinating = {
            MonetizationManager.shared
        },
        applySuperwallStatus: @escaping @MainActor (SuperwallKit.SubscriptionStatus) -> Void = {
            Superwall.shared.subscriptionStatus = $0
        },
        executor: RevenueCatPurchaseExecutor? = nil
    ) {
        self.coordinator = coordinator
        self.applySuperwallStatus = applySuperwallStatus
        self.executor = executor ?? RevenueCatPurchaseExecutor(
            applySubscriptionStatus: { entitlementIDs in
                applySuperwallStatus(Self.subscriptionStatus(for: entitlementIDs))
            },
            refreshEntitlementState: {
                await coordinator().refreshEntitlements(force: true)
            }
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
                userCancelled: result.userCancelled,
                activeEntitlementIDs: Set(
                    result.customerInfo.entitlements.activeInCurrentEnvironment.keys
                )
            )
        }
    }

    func restorePurchases() async -> RestorationResult {
        await executor.executeRestore { [coordinator] in
            guard coordinator().isRevenueCatConfigured else {
                throw RevenueCatPurchaseControllerError.monetizationUnavailable
            }

            // The restore publishes what RevenueCat resolved for *this* call rather than the stored
            // `entitlementState`, which a pending identity transition can hold at `.unknown`.
            switch try await coordinator().restorePurchases() {
            case .unknown:
                // An unresolved answer is not evidence of a lapse, so it fails the restore instead
                // of reporting an empty entitlement set - that would publish `.inactive` and flash
                // the paywall over a real subscriber.
                throw RevenueCatPurchaseControllerError.noActiveEntitlement
            case .inactive:
                return []
            case .active(let entitlementIDs):
                return entitlementIDs
            }
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
