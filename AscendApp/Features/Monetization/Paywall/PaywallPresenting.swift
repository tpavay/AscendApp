import Foundation

@MainActor
protocol PaywallPresenting: AnyObject {
    var isConfigured: Bool { get }

    func configure(configuration: MonetizationConfiguration)
    func identify(userId: String)
    func resetIdentity()
    func updateSubscriptionStatus(entitlementIDs: Set<String>)
    func cancelPresentation()
    func register(
        placement: SuperwallPlacement,
        params: [String: Any]?,
        onOutcome: @escaping @MainActor (PaywallPresentationOutcome) -> Void
    )
    func register(
        placement: SuperwallPlacement,
        params: [String: Any]?,
        identity: MonetizationIdentityTransition,
        onOutcome: @escaping @MainActor (PaywallPresentationOutcome) -> Void
    )
}

extension PaywallPresenting {
    func updateSubscriptionStatus(entitlementIDs: Set<String>) { }
    func cancelPresentation() { }

    func register(placement: SuperwallPlacement, params: [String: Any]?) {
        register(placement: placement, params: params) { _ in }
    }

    func register(
        placement: SuperwallPlacement,
        params: [String: Any]?,
        identity: MonetizationIdentityTransition,
        onOutcome: @escaping @MainActor (PaywallPresentationOutcome) -> Void
    ) {
        register(placement: placement, params: params, onOutcome: onOutcome)
    }
}
