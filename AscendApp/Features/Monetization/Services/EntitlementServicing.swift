import Foundation

@MainActor
protocol EntitlementServicing: AnyObject {
    var entitlementState: MonetizationEntitlementState { get }
    var isConfigured: Bool { get }

    func configure(configuration: MonetizationConfiguration)
    func refreshCustomerInfo() async
    func prepareIdentity(userId: String) -> MonetizationIdentityTransition
    func identify(userId: String, transition: MonetizationIdentityTransition) async
    func prepareIdentityReset() -> MonetizationIdentityTransition
    func resetIdentity(transition: MonetizationIdentityTransition) async
    func restorePurchases() async throws
}
