import SuperwallKit
import Testing
@testable import AscendApp

@MainActor
struct RevenueCatNativeSubscriptionProviderTests {
    @Test
    func missingRevenueCatConfigurationFailsBeforeAnySingletonAccess() async {
        let coordinator = NativeProviderCoordinatorStub()
        var configurationChecks = 0
        let provider = RevenueCatNativeSubscriptionProvider(
            configuration: MonetizationConfiguration(infoDictionary: [
                MonetizationConfiguration.revenueCatYearlyProductIDInfoKey: "annual",
                MonetizationConfiguration.revenueCatMonthlyProductIDInfoKey: "monthly"
            ]),
            coordinator: { coordinator },
            isPurchasesConfigured: {
                configurationChecks += 1
                return false
            }
        )

        do {
            _ = try await provider.loadPlans()
            Issue.record("An unconfigured provider must not attempt to load plans")
        } catch let error as RevenueCatNativeSubscriptionProviderError {
            #expect(error == .notConfigured)
        } catch {
            Issue.record("Unexpected typed failure: \(error)")
        }

        let result = await provider.purchase(planID: "annual")
        guard case .failed(let error) = result else {
            Issue.record("An unconfigured provider must fail purchase recoverably")
            return
        }
        #expect(error is RevenueCatNativeSubscriptionProviderError)
        #expect(configurationChecks == 2)
    }
}

@MainActor
private final class NativeProviderCoordinatorStub: PaywallPurchaseCoordinating {
    let identityGeneration = MonetizationIdentityTransition(revision: 1, userID: "user")
    let isRevenueCatConfigured = false

    func refreshEntitlements(
        force: Bool,
        waitsForPendingIdentity: Bool
    ) async -> MonetizationEntitlementRefresh {
        .unavailable(.notConfigured)
    }

    func adoptPurchaseEntitlementState(
        _ state: MonetizationEntitlementState,
        for identity: MonetizationIdentityTransition
    ) -> Bool {
        false
    }

    func restorePurchases(
        for identity: MonetizationIdentityTransition
    ) async -> MonetizationEntitlementState {
        .unknown
    }

    func restorePurchases() async -> MonetizationEntitlementState {
        .unknown
    }
}
