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

    func setCustomerEmail(_ email: String) {
        Purchases.shared.attribution.setEmail(email)
    }

    func logOutState() async throws -> MonetizationEntitlementState {
        do {
            return Self.entitlementState(from: try await Purchases.shared.logOut())
        } catch {
            guard let state = Self.resolvedState(forLogOutError: error) else { throw error }
            return state
        }
    }

    func restorePurchasesState() async throws -> MonetizationEntitlementState {
        Self.entitlementState(from: try await Purchases.shared.restorePurchases())
    }

    /// RevenueCat refuses to log out an app user that is already anonymous, which is the state of
    /// every fresh install and every signed-out cold start. That refusal is a confirmed "nobody is
    /// signed in" answer, so it resolves as `.inactive`; every other failure returns nil and
    /// propagates, because it leaves the question genuinely unanswered.
    nonisolated static func resolvedState(
        forLogOutError error: any Error
    ) -> MonetizationEntitlementState? {
        if let errorCode = error as? ErrorCode {
            return errorCode == .logOutAnonymousUserError ? .inactive : nil
        }

        let nsError = error as NSError
        guard nsError.domain == ErrorCode.errorDomain,
              nsError.code == ErrorCode.logOutAnonymousUserError.rawValue else {
            return nil
        }

        return .inactive
    }

    /// Translates, and records the environment pair on the way past.
    ///
    /// Every reading of `CustomerInfo` lands here - the stream included - so the pair a paywall or
    /// purchase event reports is the one from the most recent answer RevenueCat actually gave,
    /// rather than the one from whichever call happened to be an entry point (#506).
    private nonisolated static func entitlementState(
        from customerInfo: CustomerInfo
    ) -> MonetizationEntitlementState {
        StoreKitEnvironmentDiagnostics.shared.record(
            holdsSandboxEntitlement: customerInfo.entitlements.holdsSandboxEntitlement
        )

        return customerInfo.entitlements.appAccessEntitlementState
    }
}
