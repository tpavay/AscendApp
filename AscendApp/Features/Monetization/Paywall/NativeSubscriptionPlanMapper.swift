import Foundation

enum NativeTrialEligibility: Equatable, Sendable {
    case eligible
    case ineligible
    case unknown
}

struct NativeSubscriptionPeriod: Equatable, Sendable {
    enum Unit: Equatable, Sendable {
        case day
        case week
        case month
        case year
        case unknown
    }

    let value: Int
    let unit: Unit
}

struct NativeSubscriptionProductTerms: Equatable, Sendable {
    let productID: String
    let localizedPrice: String
    let renewalPeriod: NativeSubscriptionPeriod?
    let freeTrialPeriod: NativeSubscriptionPeriod?
}

enum NativeSubscriptionPlanMapper {
    static func plans(
        from products: [NativeSubscriptionProductTerms],
        eligibilityByProductID: [String: NativeTrialEligibility],
        yearlyProductID: String,
        monthlyProductID: String,
        locale: Locale = .current,
        bundle: Bundle = .main
    ) -> [NativeSubscriptionPlan] {
        let localizedBundle = localizedBundle(for: locale, fallback: bundle)
        let productsByID = Dictionary(
            uniqueKeysWithValues: products.map { ($0.productID, $0) }
        )

        return [yearlyProductID, monthlyProductID].compactMap { productID in
            guard let product = productsByID[productID] else { return nil }
            let renewalDescription = product.renewalPeriod.map {
                renewalText(
                    for: $0,
                    locale: locale,
                    localizedBundle: localizedBundle,
                    fallbackBundle: bundle
                )
            } ?? String(
                format: String(
                    localized: "subscription.renewal.automatic",
                    defaultValue: "Renews automatically",
                    bundle: localizedBundle,
                    locale: locale
                )
            )
            let trialDescription: String?
            let trialActionDescription: String?
            if productID == yearlyProductID,
               eligibilityByProductID[productID] == .eligible,
               let freeTrialPeriod = product.freeTrialPeriod {
                let duration = trialDurationText(
                    for: freeTrialPeriod,
                    locale: locale,
                    bundle: bundle
                )
                trialDescription = String(
                    format: String(
                        localized: "subscription.trial.free",
                        defaultValue: "%@ free",
                        bundle: localizedBundle,
                        locale: locale
                    ),
                    locale: locale,
                    duration
                )
                trialActionDescription = trialActionText(
                    for: freeTrialPeriod,
                    duration: duration,
                    locale: locale,
                    bundle: localizedBundle
                )
            } else {
                trialDescription = nil
                trialActionDescription = nil
            }

            return NativeSubscriptionPlan(
                id: productID,
                title: productID == yearlyProductID
                    ? String(
                        localized: "subscription.plan.annual",
                        defaultValue: "Annual",
                        bundle: localizedBundle,
                        locale: locale
                    )
                    : String(
                        localized: "subscription.plan.monthly",
                        defaultValue: "Monthly",
                        bundle: localizedBundle,
                        locale: locale
                    ),
                localizedPrice: product.localizedPrice,
                renewalDescription: renewalDescription,
                trialDescription: trialDescription,
                trialActionDescription: trialActionDescription
            )
        }
    }

    private static func renewalText(
        for period: NativeSubscriptionPeriod,
        locale: Locale,
        localizedBundle: Bundle,
        fallbackBundle: Bundle
    ) -> String {
        switch (period.value, period.unit) {
        case (1, .year):
            return String(
                localized: "subscription.renewal.annual",
                defaultValue: "Renews annually",
                bundle: localizedBundle,
                locale: locale
            )
        case (1, .month):
            return String(
                localized: "subscription.renewal.monthly",
                defaultValue: "Renews monthly",
                bundle: localizedBundle,
                locale: locale
            )
        default:
            break
        }
        return String(
            format: String(
                localized: "subscription.renewal.every",
                defaultValue: "Renews every %@",
                bundle: localizedBundle,
                locale: locale
            ),
            locale: locale,
            durationText(for: period, locale: locale, bundle: fallbackBundle)
        )
    }

    private static func trialDurationText(
        for period: NativeSubscriptionPeriod,
        locale: Locale,
        bundle: Bundle
    ) -> String {
        // StoreKit represents Ascend's seven-day trial as one week. Spell out seven days in the
        // customer-facing action so the promise exactly matches the configured offer.
        let displayPeriod = period.value == 1 && period.unit == .week
            ? NativeSubscriptionPeriod(value: 7, unit: .day)
            : period
        return durationText(for: displayPeriod, locale: locale, bundle: bundle)
    }

    private static func trialActionText(
        for period: NativeSubscriptionPeriod,
        duration: String,
        locale: Locale,
        bundle: Bundle
    ) -> String {
        if period.value == 1, period.unit == .week {
            return String(
                localized: "subscription.trial.action.seven_day",
                defaultValue: "Start 7-day free trial",
                bundle: bundle,
                locale: locale
            )
        }
        return String(
            format: String(
                localized: "subscription.trial.action",
                defaultValue: "Start %@ free trial",
                bundle: bundle,
                locale: locale
            ),
            locale: locale,
            duration
        )
    }

    private static func durationText(
        for period: NativeSubscriptionPeriod,
        locale: Locale,
        bundle: Bundle
    ) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        let components: DateComponents
        switch period.unit {
        case .day:
            components = DateComponents(day: period.value)
        case .week:
            components = DateComponents(weekOfMonth: period.value)
        case .month:
            components = DateComponents(month: period.value)
        case .year:
            components = DateComponents(year: period.value)
        case .unknown:
            return String(
                localized: "subscription.period.generic",
                defaultValue: "billing period",
                bundle: bundle,
                locale: locale
            )
        }
        return formatter.string(from: components) ?? "\(period.value)"
    }

    private static func localizedBundle(for locale: Locale, fallback bundle: Bundle) -> Bundle {
        guard let languageCode = locale.language.languageCode?.identifier,
              let path = bundle.path(forResource: languageCode, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else {
            return bundle
        }
        return localizedBundle
    }
}
