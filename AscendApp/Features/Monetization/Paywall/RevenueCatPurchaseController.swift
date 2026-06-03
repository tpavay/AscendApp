import Foundation
import RevenueCat
import StoreKit
import SuperwallKit

enum RevenueCatPurchaseControllerError: LocalizedError {
    case missingStoreKitProduct

    var errorDescription: String? {
        switch self {
        case .missingStoreKitProduct:
            return "Superwall did not provide a StoreKit 2 product for RevenueCat to purchase."
        }
    }
}

final class RevenueCatPurchaseController: PurchaseController {
    private var subscriptionStatusTask: Task<Void, Never>?

    @MainActor
    func syncSubscriptionStatus() {
        guard Purchases.isConfigured else { return }

        subscriptionStatusTask?.cancel()
        subscriptionStatusTask = Task {
            for await customerInfo in Purchases.shared.customerInfoStream {
                let entitlements = customerInfo.entitlements.activeInCurrentEnvironment.keys.map {
                    SuperwallKit.Entitlement(id: $0)
                }

                await MainActor.run {
                    Superwall.shared.subscriptionStatus = entitlements.isEmpty
                        ? .inactive
                        : .active(Set(entitlements))
                }
            }
        }
    }

    @MainActor
    func purchase(product: SuperwallKit.StoreProduct) async -> PurchaseResult {
        do {
            guard let sk2Product = product.sk2Product else {
                throw RevenueCatPurchaseControllerError.missingStoreKitProduct
            }

            let storeProduct = RevenueCat.StoreProduct(sk2Product: sk2Product)
            let result = try await Purchases.shared.purchase(product: storeProduct)

            return result.userCancelled ? .cancelled : .purchased
        } catch let error as ErrorCode {
            return error == .paymentPendingError ? .pending : .failed(error)
        } catch {
            return .failed(error)
        }
    }

    @MainActor
    func restorePurchases() async -> RestorationResult {
        do {
            _ = try await Purchases.shared.restorePurchases()
            return .restored
        } catch {
            return .failed(error)
        }
    }
}
