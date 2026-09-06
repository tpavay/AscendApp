import Foundation

@MainActor
protocol EntitlementServicing: AnyObject {
    var entitlementState: MonetizationEntitlementState { get }
    var hasFailedIdentityResolution: Bool { get }
    /// The identity generation the current `entitlementState` belongs to, or `nil` while no
    /// identity is settled. Re-reading it across a suspension is how a caller proves the answer it
    /// resolved earlier still describes the climber the app holds access for.
    var identityGeneration: MonetizationIdentityTransition? { get }
    var isConfigured: Bool { get }

    func configure(configuration: MonetizationConfiguration)
    /// - Parameter waitsForPendingIdentity: When true, an unresolved identity mutation is awaited
    ///   instead of short-circuiting, so the answer describes the identity the caller is acting for
    ///   rather than the transitional `.unknown` that stands while a sign-in is in flight.
    /// - Returns: Whether a current answer was established at all. A caller that decides something
    ///   from this must never read `entitlementState` when the refresh reports `.unavailable`.
    @discardableResult
    func refreshCustomerInfo(waitsForPendingIdentity: Bool) async -> MonetizationEntitlementRefresh
    func prepareIdentity(_ customer: MonetizationCustomerIdentity) -> MonetizationIdentityTransition
    func identify(
        _ customer: MonetizationCustomerIdentity,
        transition: MonetizationIdentityTransition
    ) async
    func prepareIdentityReset() -> MonetizationIdentityTransition
    func resetIdentity(transition: MonetizationIdentityTransition) async
    func retryIdentityResolution() async
    /// Accepts a RevenueCat answer only when it still belongs to the exact settled identity that
    /// started the transaction.
    @discardableResult
    func adoptTransactionState(
        _ state: MonetizationEntitlementState,
        for identity: MonetizationIdentityTransition
    ) -> Bool

    /// - Returns: The state RevenueCat resolved for the restore after it has been adopted for the
    ///   exact identity that started the operation.
    @discardableResult
    func restorePurchases(
        for identity: MonetizationIdentityTransition
    ) async throws -> MonetizationEntitlementState
    @discardableResult
    func restorePurchases() async throws -> MonetizationEntitlementState

    /// Publishes identity-guarded entitlement changes to presentation-only consumers.
    func setEntitlementStateObserver(
        _ observer: (@MainActor (MonetizationEntitlementState) -> Void)?
    )
}

extension EntitlementServicing {
    /// The background freshness pass. It neither waits for an unresolved identity mutation nor
    /// re-drives one, because a routing or lifecycle refresh has nothing to decide from a
    /// transitional answer and stalling its `.task` chain on one buys the caller nothing.
    @discardableResult
    func refreshCustomerInfo() async -> MonetizationEntitlementRefresh {
        await refreshCustomerInfo(waitsForPendingIdentity: false)
    }

    func setEntitlementStateObserver(
        _ observer: (@MainActor (MonetizationEntitlementState) -> Void)?
    ) { }

    func adoptTransactionState(
        _ state: MonetizationEntitlementState,
        for identity: MonetizationIdentityTransition
    ) -> Bool {
        false
    }

    func restorePurchases(
        for identity: MonetizationIdentityTransition
    ) async throws -> MonetizationEntitlementState {
        try await restorePurchases()
    }
}
