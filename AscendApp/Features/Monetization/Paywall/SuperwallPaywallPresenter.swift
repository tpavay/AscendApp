import Foundation
import SuperwallKit

@MainActor
final class SuperwallPaywallPresenter: PaywallPresenting {
    static let shared = SuperwallPaywallPresenter()

    private(set) var isConfigured = false
    private let purchaseController = RevenueCatPurchaseController()

    func configure(configuration: MonetizationConfiguration = .live) {
        guard !isConfigured else { return }
        guard configuration.revenueCatAPIKey != nil else { return }
        guard let apiKey = configuration.superwallAPIKey else { return }

        let options = SuperwallOptions()
        options.testModeBehavior = configuration.isSuperwallTestModeEnabled ? .always : .never

        Superwall.configure(
            apiKey: apiKey,
            purchaseController: purchaseController,
            options: options
        )
        purchaseController.syncSubscriptionStatus()
        isConfigured = true
    }

    func identify(userId: String) {
        guard isConfigured else { return }
        Superwall.shared.identify(userId: userId)
    }

    func resetIdentity() {
        guard isConfigured else { return }
        Superwall.shared.reset()
    }

    func register(placement: SuperwallPlacement, params: [String: Any]? = nil) {
        guard isConfigured else { return }
        Superwall.shared.register(
            placement: placement.rawValue,
            params: params
        )
    }
}
