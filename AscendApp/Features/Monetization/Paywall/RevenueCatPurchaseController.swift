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

    @MainActor
    func purchase(product: SuperwallKit.StoreProduct) async -> PurchaseResult {
        do {
            guard let sk2Product = product.sk2Product else {
                throw RevenueCatPurchaseControllerError.missingStoreKitProduct
            }

            let storeProduct = RevenueCat.StoreProduct(sk2Product: sk2Product)
            let result = try await Purchases.shared.purchase(product: storeProduct)
            let outcome = result.userCancelled ? "cancelled" : "purchased"

            if !result.userCancelled {
                applySubscriptionStatus(from: result.customerInfo)
                await RevenueCatEntitlementService.shared.refreshCustomerInfo()
            }

            TelemetryManager.shared.track(
                PaywallAnalyticsEvent.purchaseControllerCompleted(
                    productID: product.productIdentifier,
                    outcome: outcome
                )
            )

            return result.userCancelled ? .cancelled : .purchased
        } catch let error as ErrorCode {
            let outcome = error == .paymentPendingError ? "pending" : "failed"
            TelemetryManager.shared.track(
                PaywallAnalyticsEvent.purchaseControllerCompleted(
                    productID: product.productIdentifier,
                    outcome: outcome
                )
            )

            return error == .paymentPendingError ? .pending : .failed(error)
        } catch {
            TelemetryManager.shared.track(
                PaywallAnalyticsEvent.purchaseControllerCompleted(
                    productID: product.productIdentifier,
                    outcome: "failed"
                )
            )

            return .failed(error)
        }
    }

    @MainActor
    func restorePurchases() async -> RestorationResult {
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            applySubscriptionStatus(from: customerInfo)
            await RevenueCatEntitlementService.shared.refreshCustomerInfo()
            TelemetryManager.shared.track(
                PaywallAnalyticsEvent.restoreControllerCompleted(outcome: "restored")
            )
            return .restored
        } catch {
            TelemetryManager.shared.track(
                PaywallAnalyticsEvent.restoreControllerCompleted(outcome: "failed")
            )
            return .failed(error)
        }
    }

    @MainActor
    private func applySubscriptionStatus(from customerInfo: RevenueCat.CustomerInfo) {
        let entitlements = customerInfo.entitlements.activeInCurrentEnvironment.keys.map {
            SuperwallKit.Entitlement(id: $0)
        }

        Superwall.shared.subscriptionStatus = entitlements.isEmpty
            ? .inactive
            : .active(Set(entitlements))
    }
}
