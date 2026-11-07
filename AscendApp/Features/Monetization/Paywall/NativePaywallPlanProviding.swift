import Foundation
import SuperwallKit

@MainActor
protocol NativePaywallPlanProviding: AnyObject {
    func loadPlans() async throws -> [NativePaywallPlan]
    func purchase(planID: String) async -> PurchaseResult
}
