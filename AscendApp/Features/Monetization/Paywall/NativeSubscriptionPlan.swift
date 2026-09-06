import Foundation

struct NativeSubscriptionPlan: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let localizedPrice: String
    let renewalDescription: String
    let trialDescription: String?
    let trialActionDescription: String?

    init(
        id: String,
        title: String,
        localizedPrice: String,
        renewalDescription: String,
        trialDescription: String?,
        trialActionDescription: String? = nil
    ) {
        self.id = id
        self.title = title
        self.localizedPrice = localizedPrice
        self.renewalDescription = renewalDescription
        self.trialDescription = trialDescription
        self.trialActionDescription = trialActionDescription
    }

    var purchaseActionTitle: String {
        trialActionDescription ?? String(
            localized: "subscription.action.subscribe",
            defaultValue: "Subscribe with Apple"
        )
    }
}
