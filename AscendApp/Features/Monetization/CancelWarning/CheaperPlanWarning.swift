import Foundation

/// The "Heads up" a climber sees before cancelling a plan that costs less than the standard
/// yearly plan does today. It exists to inform; it never gates cancelling.
struct CheaperPlanWarning: Equatable, Sendable {
    static let title = "Heads up"
    static let keepButtonTitle = "Keep my plan"
    static let continueButtonTitle = "Continue to cancel"

    let heldRate: SubscriptionRate
    let standardRate: SubscriptionRate
    let percentCheaper: Int
    let isInFreeTrial: Bool

    /// A climber still inside a free trial has paid nothing, so the sentence says what the rate
    /// is rather than what they pay.
    var message: String {
        let opening = isInFreeTrial ? "Your rate is" : "You currently pay"
        return "\(opening) \(heldRate.formattedPrice) per \(heldRate.period.phrase). "
            + "That's \(percentCheaper)% cheaper than the current "
            + "\(standardRate.formattedPrice) per \(standardRate.period.phrase). "
            + "If you cancel, you may not be able to get that rate again."
    }
}

/// Decides whether a climber on `held` is on a plan cheaper than `standardYearly`.
///
/// A pure function of two values the store reports: nothing is hardcoded, so a price the captain
/// changes in App Store Connect, a welcome product, and a grandfathered price all resolve from the
/// same comparison.
enum CheaperPlanWarningPolicy {
    /// A rate that rounds to under one percent cheaper is the same rate as far as a climber can
    /// tell, and "0% cheaper" is not a warning anyone should read.
    private static let smallestWholePercent = 1

    static func warning(
        for held: HeldPlan?,
        standardYearly: SubscriptionRate?
    ) -> CheaperPlanWarning? {
        guard case .subscription(let heldRate, let isInFreeTrial, let willAutoRenew) = held,
              willAutoRenew,
              let standardYearly,
              // Two currencies cannot be compared without a rate nobody here has, so a storefront
              // that reports them differently gets no warning rather than a wrong percentage.
              heldRate.currencyCode == standardYearly.currencyCode,
              heldRate.price > 0,
              standardYearly.yearlyEquivalent > 0 else { return nil }

        let held = heldRate.yearlyEquivalent
        let standard = standardYearly.yearlyEquivalent
        guard held < standard else { return nil }

        let percent = wholePercent(saving: standard - held, of: standard)
        guard percent >= smallestWholePercent else { return nil }

        return CheaperPlanWarning(
            heldRate: heldRate,
            standardRate: standardYearly,
            percentCheaper: percent,
            isInFreeTrial: isInFreeTrial
        )
    }

    private static func wholePercent(saving: Decimal, of whole: Decimal) -> Int {
        var ratio = saving / whole * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &ratio, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}

/// The storefront's own currency formatting, so a price reads as it does on the paywall.
enum SubscriptionRatePriceFormatter {
    static func string(price: Decimal, currencyCode: String, locale: Locale) -> String {
        price.formatted(.currency(code: currencyCode).locale(locale))
    }
}
