import Foundation

@MainActor
protocol EntitlementServicing: AnyObject {
    var entitlementState: MonetizationEntitlementState { get }
    var isConfigured: Bool { get }

    func configure(configuration: MonetizationConfiguration)
    func refreshCustomerInfo() async
    func identify(userId: String) async
    func resetIdentity() async
    func restorePurchases() async throws
}
