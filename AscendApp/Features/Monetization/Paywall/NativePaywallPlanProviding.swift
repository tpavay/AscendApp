import Foundation
import SuperwallKit

@MainActor
protocol NativePaywallPlanProviding: AnyObject {
    func loadPlans() async throws -> [NativePaywallPlan]
    func purchase(planID: String) async -> PurchaseResult
}

/// What the onboarding paywall needs beyond the gate's two launch plans: the welcome gift's yearly
/// plan, loaded beside them.
@MainActor
protocol OnboardingPaywallPlanProviding: NativePaywallPlanProviding {
    func loadOnboardingPlans() async throws -> [NativePaywallPlan]
}

extension RevenueCatNativePaywallPlanProvider: OnboardingPaywallPlanProviding { }
