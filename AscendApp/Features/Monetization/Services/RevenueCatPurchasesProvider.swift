import Foundation
import RevenueCat

@MainActor
final class RevenueCatPurchasesProvider: RevenueCatEntitlementProviding {
    var customerInfoUpdates: AsyncStream<MonetizationEntitlementState> {
        AsyncStream { continuation in
            let task = Task {
                for await customerInfo in Purchases.shared.customerInfoStream {
                    guard !Task.isCancelled else { break }
                    continuation.yield(Self.entitlementState(from: customerInfo))
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func customerInfoState() async throws -> MonetizationEntitlementState {
        Self.entitlementState(from: try await Purchases.shared.customerInfo())
    }

    func logInState(userID: String) async throws -> MonetizationEntitlementState {
        let result = try await Purchases.shared.logIn(userID)
        return Self.entitlementState(from: result.customerInfo)
    }

    /// RevenueCat refuses to log out an app user that is already anonymous, which is the state of
    /// every fresh install and every signed-out cold start. That refusal is a confirmed "nobody is
    /// signed in" answer, so it resolves as `.inactive` instead of surfacing as an unanswered state.
    func logOutState() async throws -> MonetizationEntitlementState {
        do {
            return Self.entitlementState(from: try await Purchases.shared.logOut())
        } catch {
            guard Self.isAlreadyAnonymousRefusal(error) else { throw error }
            return .inactive
        }
    }

    func restorePurchasesState() async throws -> MonetizationEntitlementState {
        Self.entitlementState(from: try await Purchases.shared.restorePurchases())
    }

    private nonisolated static func isAlreadyAnonymousRefusal(_ error: any Error) -> Bool {
        if let errorCode = error as? ErrorCode {
            return errorCode == .logOutAnonymousUserError
        }

        let nsError = error as NSError
        return nsError.domain == ErrorCode.errorDomain
            && nsError.code == ErrorCode.logOutAnonymousUserError.rawValue
    }

    private nonisolated static func entitlementState(
        from customerInfo: CustomerInfo
    ) -> MonetizationEntitlementState {
        let activeEntitlementIDs = Set(customerInfo.entitlements.activeInCurrentEnvironment.keys)

        return activeEntitlementIDs.isEmpty
            ? .inactive
            : .active(activeEntitlementIDs)
    }
}
