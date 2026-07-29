import Foundation
import RevenueCat

@MainActor
final class RevenueCatPurchasesProvider: RevenueCatEntitlementProviding {
    var customerInfoUpdates: AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await _ in Purchases.shared.customerInfoStream {
                    guard !Task.isCancelled else { break }
                    continuation.yield()
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func customerInfoState() async throws -> MonetizationEntitlementState {
        entitlementState(from: try await Purchases.shared.customerInfo())
    }

    func logInState(userID: String) async throws -> MonetizationEntitlementState {
        let result = try await Purchases.shared.logIn(userID)
        return entitlementState(from: result.customerInfo)
    }

    func logOutState() async throws -> MonetizationEntitlementState {
        entitlementState(from: try await Purchases.shared.logOut())
    }

    func restorePurchasesState() async throws -> MonetizationEntitlementState {
        entitlementState(from: try await Purchases.shared.restorePurchases())
    }

    private func entitlementState(from customerInfo: CustomerInfo) -> MonetizationEntitlementState {
        let activeEntitlementIDs = Set(customerInfo.entitlements.activeInCurrentEnvironment.keys)

        return activeEntitlementIDs.isEmpty
            ? .inactive
            : .active(activeEntitlementIDs)
    }
}
