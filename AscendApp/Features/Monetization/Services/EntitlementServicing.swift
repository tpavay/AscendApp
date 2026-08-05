import Foundation

@MainActor
protocol EntitlementServicing: AnyObject {
    var entitlementState: MonetizationEntitlementState { get }
    var hasFailedIdentityResolution: Bool { get }
    var isConfigured: Bool { get }

    func configure(configuration: MonetizationConfiguration)
    func refreshCustomerInfo() async
    func prepareIdentity(userId: String) -> MonetizationIdentityTransition
    func identify(userId: String, transition: MonetizationIdentityTransition) async
    func prepareIdentityReset() -> MonetizationIdentityTransition
    func resetIdentity(transition: MonetizationIdentityTransition) async
    func retryIdentityResolution() async
    /// - Returns: The state RevenueCat resolved for the restore, which is authoritative even when
    ///   a pending identity transition refuses to let it become `entitlementState`.
    @discardableResult
    func restorePurchases() async throws -> MonetizationEntitlementState
}
