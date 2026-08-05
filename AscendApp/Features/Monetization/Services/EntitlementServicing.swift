import Foundation

@MainActor
protocol EntitlementServicing: AnyObject {
    var entitlementState: MonetizationEntitlementState { get }
    var hasFailedIdentityResolution: Bool { get }
    var isConfigured: Bool { get }

    func configure(configuration: MonetizationConfiguration)
    /// - Parameter waitsForPendingIdentity: When true, an unresolved identity mutation is awaited
    ///   instead of short-circuiting, so the answer describes the identity the caller is acting for
    ///   rather than the transitional `.unknown` that stands while a sign-in is in flight.
    /// - Returns: Whether a current answer was established at all. A caller that decides something
    ///   from this must never read `entitlementState` when the refresh reports `.unavailable`.
    @discardableResult
    func refreshCustomerInfo(waitsForPendingIdentity: Bool) async -> MonetizationEntitlementRefresh
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

extension EntitlementServicing {
    /// The background freshness pass. It neither waits for an unresolved identity mutation nor
    /// re-drives one, because a routing or lifecycle refresh has nothing to decide from a
    /// transitional answer and stalling its `.task` chain on one buys the caller nothing.
    @discardableResult
    func refreshCustomerInfo() async -> MonetizationEntitlementRefresh {
        await refreshCustomerInfo(waitsForPendingIdentity: false)
    }
}
