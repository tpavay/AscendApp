import Foundation
import RevenueCat
import StoreKit
import SuperwallKit

enum RevenueCatPurchaseControllerError: LocalizedError {
    case missingStoreKitProduct
    case monetizationUnavailable

    var errorDescription: String? {
        switch self {
        case .missingStoreKitProduct:
            return "Superwall did not provide a StoreKit 2 product for RevenueCat to purchase."
        case .monetizationUnavailable:
            return "Ascend could not reach the App Store. Check your connection and try again."
        }
    }
}

final class RevenueCatPurchaseController: PurchaseController {
    // Resolved on use, not at init: `MonetizationManager.shared` owns the Superwall presenter that
    // owns this controller, so reading it here would re-enter a static initializer still running.
    private let coordinator: @MainActor () -> any PaywallPurchaseCoordinating
    private let applySuperwallStatus: @MainActor (SuperwallKit.SubscriptionStatus) -> Void

    private var subscriptionStatusTask: Task<Void, Never>?

    init(
        coordinator: @escaping @MainActor () -> any PaywallPurchaseCoordinating = {
            MonetizationManager.shared
        },
        applySuperwallStatus: @escaping @MainActor (SuperwallKit.SubscriptionStatus) -> Void = {
            Superwall.shared.subscriptionStatus = $0
        }
    ) {
        self.coordinator = coordinator
        self.applySuperwallStatus = applySuperwallStatus
    }

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
                await coordinator().refreshEntitlements(force: true)
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
        guard coordinator().isRevenueCatConfigured else {
            TelemetryManager.shared.track(
                PaywallAnalyticsEvent.restoreControllerCompleted(outcome: "failed")
            )
            return .failed(RevenueCatPurchaseControllerError.monetizationUnavailable)
        }

        do {
            applySubscriptionStatus(from: try await coordinator().restorePurchases())
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
        applySuperwallStatus(
            subscriptionStatus(for: Set(customerInfo.entitlements.activeInCurrentEnvironment.keys))
        )
    }

    /// An unresolved entitlement answer leaves Superwall's status alone: it is not evidence of a
    /// lapse, and publishing `.inactive` would flash the paywall over a real subscriber.
    @MainActor
    private func applySubscriptionStatus(from state: MonetizationEntitlementState) {
        switch state {
        case .unknown:
            return
        case .inactive:
            applySuperwallStatus(subscriptionStatus(for: []))
        case .active(let entitlementIDs):
            applySuperwallStatus(subscriptionStatus(for: entitlementIDs))
        }
    }

    private func subscriptionStatus(for entitlementIDs: Set<String>)
        -> SuperwallKit.SubscriptionStatus {
        let entitlements = entitlementIDs.map { SuperwallKit.Entitlement(id: $0) }

        return entitlements.isEmpty ? .inactive : .active(Set(entitlements))
    }
}
