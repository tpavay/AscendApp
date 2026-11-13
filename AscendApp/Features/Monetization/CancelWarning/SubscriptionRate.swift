import Foundation

/// How often a plan bills, in the units StoreKit reports, kept apart from `StoreKit` so the
/// eligibility rule can be tested without a store.
struct RatePeriod: Equatable, Hashable, Sendable {
    enum Unit: String, Equatable, Hashable, Sendable {
        case day
        case week
        case month
        case year
    }

    let unit: Unit
    let value: Int

    static let year = RatePeriod(unit: .year, value: 1)
    static let month = RatePeriod(unit: .month, value: 1)

    /// How many billing periods fit in one year, which is what lets a monthly price be set beside
    /// a yearly one. A week is a seventh of 365 days rather than 52 whole weeks, so a weekly plan
    /// is not flattered by the leftover day.
    var periodsPerYear: Decimal {
        let count = Decimal(max(value, 1))
        switch unit {
        case .day: return 365 / count
        case .week: return Decimal(365) / 7 / count
        case .month: return 12 / count
        case .year: return 1 / count
        }
    }

    /// The words that follow "per": `year`, `month`, or `3 months` for a plan that bills less
    /// often than its unit.
    var phrase: String {
        value <= 1 ? unit.rawValue : "\(value) \(unit.rawValue)s"
    }
}

/// What a plan costs each time it bills, the price already formatted for the climber's storefront.
///
/// The number and the string travel together because the policy compares the number and the copy
/// prints the string - two different needs that must never be re-derived from each other, since
/// only StoreKit knows the storefront's currency and locale.
struct SubscriptionRate: Equatable, Sendable {
    let productID: String
    let price: Decimal
    let currencyCode: String
    let period: RatePeriod
    let formattedPrice: String

    /// What the plan costs over a year at this price, for comparing a monthly plan with a yearly one.
    var yearlyEquivalent: Decimal { price * period.periodsPerYear }
}

/// What the climber holds that bears on cancelling, as the store and RevenueCat report it now.
enum HeldPlan: Equatable, Sendable {
    /// An auto-renewing subscription the climber can cancel.
    case subscription(
        rate: SubscriptionRate,
        isInFreeTrial: Bool,
        // False once the climber has already cancelled: there is nothing left to warn about.
        willAutoRenew: Bool
    )
    /// A one-time purchase. There is no recurring rate to lose and nothing to cancel.
    case lifetime
}
