import Foundation
import SuperwallKit

@MainActor
protocol NativePaywallPlanProviding: AnyObject {
    func loadPlans() async throws -> [NativePaywallPlan]
    func purchase(planID: String) async -> PurchaseResult
}

/// What the pre-sign-in paywall needs beyond the signed-in gate's two launch plans: the welcome
/// gift's yearly plan, loaded beside them.
@MainActor
protocol PreAuthPaywallPlanProviding: NativePaywallPlanProviding {
    func loadPreAuthPlans() async throws -> [NativePaywallPlan]
}

extension RevenueCatNativePaywallPlanProvider: PreAuthPaywallPlanProviding { }
