import Foundation

@MainActor
protocol PaywallPresenting: AnyObject {
    var isConfigured: Bool { get }

    func configure(configuration: MonetizationConfiguration)
    func identify(userId: String)
    func resetIdentity()
    func register(
        placement: SuperwallPlacement,
        params: [String: Any]?,
        onOutcome: @escaping @MainActor (PaywallPresentationOutcome) -> Void
    )
}

extension PaywallPresenting {
    func register(placement: SuperwallPlacement, params: [String: Any]?) {
        register(placement: placement, params: params) { _ in }
    }
}
