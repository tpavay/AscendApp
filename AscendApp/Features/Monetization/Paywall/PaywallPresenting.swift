import Foundation

@MainActor
protocol PaywallPresenting: AnyObject {
    var isConfigured: Bool { get }

    func configure(configuration: MonetizationConfiguration)
    func identify(userId: String)
    func resetIdentity()
    func register(placement: SuperwallPlacement, params: [String: Any]?)
}
