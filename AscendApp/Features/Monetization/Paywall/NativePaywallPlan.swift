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
    /// The price as a number, so a discount between two plans is computed from what the store
    /// charges rather than typed. `nil` for a plan built without one.
    let price: Decimal?
    /// The store's own per-month rendering of an annual price ("$2.49"), `nil` for a one-time
    /// purchase.
    let localizedPricePerMonth: String?
    /// The free period, present only when the product carries one and the Apple ID can still take
    /// it - the same condition that fills ``trialDescription``.
    let freeTrialPeriod: NativeSubscriptionPeriod?

    init(
        id: String,
        title: String,
        localizedPrice: String,
        billing: Billing = .subscription,
        billingDescription: String,
        trialDescription: String?,
        trialActionDescription: String? = nil,
        price: Decimal? = nil,
        localizedPricePerMonth: String? = nil,
        freeTrialPeriod: NativeSubscriptionPeriod? = nil
    ) {
        self.id = id
        self.title = title
        self.localizedPrice = localizedPrice
        self.billing = billing
        self.billingDescription = billingDescription
        self.trialDescription = trialDescription
        self.trialActionDescription = trialActionDescription
        self.price = price
        self.localizedPricePerMonth = localizedPricePerMonth
        self.freeTrialPeriod = freeTrialPeriod
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
