import Foundation
import Testing
@testable import AscendApp

// A purchase belongs to an account: an anonymous RevenueCat customer has no uid to attribute a
// charge to, and a charge nobody can attach to a climber is the one thing the executor refuses.

@MainActor
@Suite
struct PurchaseIdentityTests {
    private func executor(identity: MonetizationIdentityTransition?) -> RevenueCatPurchaseExecutor {
        RevenueCatPurchaseExecutor(
            transactionContextStore: PaywallTransactionContextStore(),
            entitlementID: "app_access",
            applySubscriptionStatus: { _ in },
            refreshEntitlementState: { .refreshed(.unknown) },
            currentIdentityGeneration: { identity },
            adoptEntitlementState: { _, _ in true }
        )
    }

    @Test
    func aSignedInAccountBuys() async {
        let account = MonetizationIdentityTransition(revision: 3, userID: "u1")
        let result = await executor(identity: account).executePurchase(productID: "y") {
            .init(userCancelled: false, entitlementState: .active(["app_access"]))
        }

        guard case .purchased = result else { Issue.record("expected a purchase, got \(result)"); return }
    }

    @Test
    func aPurchaseWithNoUidIsRefusedBeforeAnythingIsCharged() async {
        var ran = false
        let anonymous = MonetizationIdentityTransition(revision: 3, userID: nil)
        let result = await executor(identity: anonymous).executePurchase(productID: "y") {
            ran = true
            return .init(userCancelled: false, entitlementState: .active(["app_access"]))
        }

        #expect(!ran)
        guard case .failed = result else { Issue.record("expected a refusal"); return }
    }

    @Test
    func anAccountThatChangesWhileStoreKitIsReadIsRefusedBeforeAnythingIsCharged() async {
        var current: MonetizationIdentityTransition? = MonetizationIdentityTransition(
            revision: 3,
            userID: "u1"
        )
        var holds: [PendingPurchaseHold] = []
        var ran = false
        let executor = RevenueCatPurchaseExecutor(
            transactionContextStore: PaywallTransactionContextStore(),
            entitlementID: "app_access",
            applySubscriptionStatus: { _ in },
            refreshEntitlementState: { .refreshed(.unknown) },
            currentIdentityGeneration: { current },
            adoptEntitlementState: { _, _ in true },
            holdPendingPurchase: { holds.append($0) },
            latestTransactionID: { _ in
                current = MonetizationIdentityTransition(revision: 4, userID: nil)
                return nil
            }
        )

        let result = await executor.executePurchase(productID: "y") {
            ran = true
            return .init(userCancelled: false, entitlementState: .active(["app_access"]))
        }

        #expect(!ran)
        #expect(holds.isEmpty)
        guard case .failed = result else { Issue.record("expected a refusal"); return }
    }

    @Test
    func noIdentityAtAllIsRefusedToo() async {
        var ran = false
        let result = await executor(identity: nil).executePurchase(productID: "y") {
            ran = true
            return .init(userCancelled: false, entitlementState: .active(["app_access"]))
        }

        #expect(!ran)
        guard case .failed = result else { Issue.record("expected a refusal"); return }
    }
}
