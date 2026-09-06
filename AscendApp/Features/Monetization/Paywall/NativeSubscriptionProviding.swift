import Foundation
import SuperwallKit

@MainActor
protocol NativeSubscriptionProviding: AnyObject {
    func loadPlans() async throws -> [NativeSubscriptionPlan]
    func purchase(planID: String) async -> PurchaseResult
}
