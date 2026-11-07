import Foundation

struct NativePaywallPlan: Equatable, Identifiable, Sendable {
    /// What the price is charged for, read from the store product rather than assumed from the
    /// plan's slot, because every sentence on the card depends on it: a one-time purchase that
    /// promised a trial or a renewal would be a lie about the charge.
    enum Billing: Equatable, Sendable {
        case subscription
        case oneTime
    }

    let id: String
    let title: String
    let localizedPrice: String
    let billing: Billing
    let billingDescription: String
    let trialDescription: String?
    let trialActionDescription: String?

    init(
        id: String,
        title: String,
        localizedPrice: String,
        billing: Billing = .subscription,
        billingDescription: String,
        trialDescription: String?,
        trialActionDescription: String? = nil
    ) {
        self.id = id
        self.title = title
        self.localizedPrice = localizedPrice
        self.billing = billing
        self.billingDescription = billingDescription
        self.trialDescription = trialDescription
        self.trialActionDescription = trialActionDescription
    }

    var purchaseActionTitle: String {
        switch billing {
        case .oneTime:
            String(
                localized: "subscription.action.buy_lifetime",
                defaultValue: "Buy Lifetime"
            )
        case .subscription:
            trialActionDescription ?? String(
                localized: "subscription.action.subscribe",
                defaultValue: "Subscribe with Apple"
            )
        }
    }
}
