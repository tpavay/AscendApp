import Foundation

/// Moves a purchase made before sign-in onto the account that just signed in, and waits until the
/// server has written the grant that paid reads require.
///
/// RevenueCat's `logIn` carries an anonymous customer's purchases onto a uid it has never seen. A uid
/// it already knows - a returning climber buying again on a new phone - keeps its own history, and
/// the anonymous purchase only follows through a restore, so a missing entitlement after sign-in is
/// restored once before the wait gives up. Nothing here decides what the climber is allowed to do:
/// the entitlement and the server grant do.
@MainActor
final class PreAuthPurchaseTransfer {
    enum Outcome: Equatable, Sendable {
        /// Nothing was bought before sign-in.
        case nothingToTransfer
        /// The account holds the entitlement and the server has written its grant.
        case granted
        /// The account holds the entitlement but the server has not answered in time. Access is not
        /// lost: reconciliation keeps running from launch, foreground and refused reads.
        case grantPending
        /// The purchase did not reach the account. The paywall after sign-in sells.
        case notTransferred
    }

    private let ledger: PreAuthPurchaseLedger
    private let monetization: any PreAuthPurchaseTransferring
    private let invoker: any AppAccessReconciliationInvoking
    private let maxAttempts: Int
    private let retryDelay: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let releaseUnconfirmedPurchase: @MainActor () -> Void

    init(
        ledger: PreAuthPurchaseLedger = PreAuthPurchaseLedger(),
        monetization: any PreAuthPurchaseTransferring = MonetizationManager.shared,
        invoker: any AppAccessReconciliationInvoking = FunctionsAppAccessReconciliationInvoker(),
        maxAttempts: Int = 6,
        retryDelay: Duration = .seconds(2),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        releaseUnconfirmedPurchase: @escaping @MainActor () -> Void = {
            OnboardingPaywallModel.live.releaseUnconfirmedPurchase()
        }
    ) {
        self.ledger = ledger
        self.monetization = monetization
        self.invoker = invoker
        self.maxAttempts = maxAttempts
        self.retryDelay = retryDelay
        self.sleep = sleep
        self.releaseUnconfirmedPurchase = releaseUnconfirmedPurchase
    }

    /// Runs after the sign-in has been identified with RevenueCat.
    func completeAfterSignIn() async -> Outcome {
        releaseUnconfirmedPurchase()

        guard ledger.progress().purchase != nil else { return .nothingToTransfer }

        guard await accountHoldsEntitlement() else { return .notTransferred }

        for attempt in 0..<maxAttempts {
            if attempt > 0 {
                do { try await sleep(retryDelay) } catch { return .grantPending }
            }

            // A throttled or failed answer is a refusal, not a verdict, so the loop asks again.
            if let outcome = try? await invoker.invokeReconciliation(), outcome == .active {
                ledger.clear()
                return .granted
            }
        }

        return .grantPending
    }

    private func accountHoldsEntitlement() async -> Bool {
        if await monetization.refreshedEntitlementIsActive() { return true }
        // The uid was already known to RevenueCat, so the anonymous purchase has not followed it.
        return await monetization.restoredEntitlementIsActive()
    }
}

/// The two RevenueCat reads the transfer needs, behind a seam so the order they run in is tested
/// without the SDK.
@MainActor
protocol PreAuthPurchaseTransferring: AnyObject {
    func refreshedEntitlementIsActive() async -> Bool
    func restoredEntitlementIsActive() async -> Bool
}

extension MonetizationManager: PreAuthPurchaseTransferring {
    func refreshedEntitlementIsActive() async -> Bool {
        guard case .refreshed(let state) = await refreshEntitlements(
            force: true,
            waitsForPendingIdentity: true
        ) else { return false }

        return state.hasActiveEntitlement(configuration.revenueCatEntitlementID)
    }

    func restoredEntitlementIsActive() async -> Bool {
        guard let state = try? await restorePurchases() else { return false }
        return state.hasActiveEntitlement(configuration.revenueCatEntitlementID)
    }
}
