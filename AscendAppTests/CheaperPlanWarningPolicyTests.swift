import Foundation
import Testing
@testable import AscendApp

/// Who gets the Heads up before cancelling, and what it says.
///
/// Every price here is a stand-in for what StoreKit reports: nothing in the rule names a number.
struct CheaperPlanWarningPolicyTests {
    private static let usLocale = Locale(identifier: "en_US")

    private static func rate(
        _ productID: String,
        _ price: Decimal,
        per period: RatePeriod,
        currency: String = "USD",
        locale: Locale = usLocale
    ) -> SubscriptionRate {
        SubscriptionRate(
            productID: productID,
            price: price,
            currencyCode: currency,
            period: period,
            formattedPrice: SubscriptionRatePriceFormatter.string(
                price: price,
                currencyCode: currency,
                locale: locale
            )
        )
    }

    private static let standardYearly = rate("ascend_yearly", 29.99, per: .year)
    private static let welcomeYearly = rate("ascend_yearly_welcome", 9.99, per: .year)

    private static func subscription(
        _ rate: SubscriptionRate,
        trial: Bool = false,
        renews: Bool = true
    ) -> HeldPlan {
        .subscription(rate: rate, isInFreeTrial: trial, willAutoRenew: renews)
    }

    // MARK: - Who is warned

    @Test
    func theWelcomeYearlyPlanIsWarned() throws {
        let warning = try #require(
            CheaperPlanWarningPolicy.warning(
                for: Self.subscription(Self.welcomeYearly),
                standardYearly: Self.standardYearly
            )
        )

        #expect(warning.percentCheaper == 67)
        #expect(warning.heldRate.formattedPrice == "$9.99")
        #expect(warning.standardRate.formattedPrice == "$29.99")
    }

    @Test
    func aLegacyCheaperPriceIsWarned() throws {
        let legacy = Self.rate("ascend_yearly", 19.99, per: .year)

        let warning = try #require(
            CheaperPlanWarningPolicy.warning(
                for: Self.subscription(legacy),
                standardYearly: Self.standardYearly
            )
        )

        #expect(warning.percentCheaper == 33)
    }

    @Test
    func aMonthlyPlanThatCostsLessOverAYearIsWarnedOnItsYearlyEquivalent() throws {
        let monthly = Self.rate("ascend_monthly", 1.99, per: .month)

        let warning = try #require(
            CheaperPlanWarningPolicy.warning(
                for: Self.subscription(monthly),
                standardYearly: Self.standardYearly
            )
        )

        // 1.99 x 12 = 23.88 against 29.99.
        #expect(warning.percentCheaper == 20)
        #expect(warning.message.contains("$1.99 per month"))
        #expect(warning.message.contains("$29.99 per year"))
    }

    // MARK: - Who is not

    @Test
    func theStandardYearlyPlanIsNotWarned() {
        #expect(
            CheaperPlanWarningPolicy.warning(
                for: Self.subscription(Self.standardYearly),
                standardYearly: Self.standardYearly
            ) == nil
        )
    }

    @Test
    func aPlanDearerThanTheStandardYearlyPlanIsNotWarned() {
        let dearer = Self.rate("ascend_yearly", 39.99, per: .year)

        #expect(
            CheaperPlanWarningPolicy.warning(
                for: Self.subscription(dearer),
                standardYearly: Self.standardYearly
            ) == nil
        )
    }

    @Test
    func theMonthlyPlanThatCostsMoreOverAYearIsNotWarned() {
        // 9.99 x 12 = 119.88 against 29.99: the monthly plan is the dear one.
        let monthly = Self.rate("ascend_monthly", 9.99, per: .month)

        #expect(
            CheaperPlanWarningPolicy.warning(
                for: Self.subscription(monthly),
                standardYearly: Self.standardYearly
            ) == nil
        )
    }

    @Test
    func aLifetimeOwnerIsNotWarned() {
        #expect(
            CheaperPlanWarningPolicy.warning(for: .lifetime, standardYearly: Self.standardYearly) == nil
        )
    }

    @Test
    func noPaidPlanIsNotWarned() {
        #expect(
            CheaperPlanWarningPolicy.warning(for: nil, standardYearly: Self.standardYearly) == nil
        )
    }

    @Test
    func aClimberWhoHasAlreadyCancelledIsNotWarned() {
        #expect(
            CheaperPlanWarningPolicy.warning(
                for: Self.subscription(Self.welcomeYearly, renews: false),
                standardYearly: Self.standardYearly
            ) == nil
        )
    }

    @Test
    func anUnknownStandardPriceIsNotWarned() {
        #expect(
            CheaperPlanWarningPolicy.warning(
                for: Self.subscription(Self.welcomeYearly),
                standardYearly: nil
            ) == nil
        )
    }

    @Test
    func ratesInDifferentCurrenciesAreNotComparedAgainstEachOther() {
        let euros = Self.rate("ascend_yearly_welcome", 9.99, per: .year, currency: "EUR")

        #expect(
            CheaperPlanWarningPolicy.warning(
                for: Self.subscription(euros),
                standardYearly: Self.standardYearly
            ) == nil
        )
    }

    @Test
    func aDifferenceThatRoundsToZeroPercentIsNotWarned() {
        // 29.89 against 29.99 is 0.33 percent cheaper.
        let almostStandard = Self.rate("ascend_yearly", 29.89, per: .year)

        #expect(
            CheaperPlanWarningPolicy.warning(
                for: Self.subscription(almostStandard),
                standardYearly: Self.standardYearly
            ) == nil
        )
    }

    // MARK: - Rounding

    @Test(arguments: [
        (Decimal(string: "24.99")!, 17),
        (Decimal(string: "14.995")!, 50),
        (Decimal(string: "29.69")!, 1),
        (Decimal(string: "9.99")!, 67)
    ])
    func thePercentageIsAWholeNumber(heldPrice: Decimal, expected: Int) throws {
        let held = Self.rate("ascend_yearly", heldPrice, per: .year)

        let warning = try #require(
            CheaperPlanWarningPolicy.warning(
                for: Self.subscription(held),
                standardYearly: Self.standardYearly
            )
        )

        #expect(warning.percentCheaper == expected)
    }

    // MARK: - Copy

    @Test
    func thePaidCopyIsTheCaptainsWording() throws {
        let warning = try #require(
            CheaperPlanWarningPolicy.warning(
                for: Self.subscription(Self.welcomeYearly),
                standardYearly: Self.standardYearly
            )
        )

        #expect(CheaperPlanWarning.title == "Heads up")
        #expect(
            warning.message == "You currently pay $9.99 per year. "
                + "That's 67% cheaper than the current $29.99 per year. "
                + "If you cancel, you may not be able to get that rate again."
        )
    }

    @Test
    func aClimberInsideAFreeTrialIsToldTheirRateNotWhatTheyPay() throws {
        let warning = try #require(
            CheaperPlanWarningPolicy.warning(
                for: Self.subscription(Self.welcomeYearly, trial: true),
                standardYearly: Self.standardYearly
            )
        )

        #expect(
            warning.message == "Your rate is $9.99 per year. "
                + "That's 67% cheaper than the current $29.99 per year. "
                + "If you cancel, you may not be able to get that rate again."
        )
        #expect(!warning.message.contains("You currently pay"))
    }

    @Test
    func aPlanThatBillsEveryThreeMonthsSaysSo() throws {
        let quarterly = Self.rate("quarterly", 4.99, per: RatePeriod(unit: .month, value: 3))

        let warning = try #require(
            CheaperPlanWarningPolicy.warning(
                for: Self.subscription(quarterly),
                standardYearly: Self.standardYearly
            )
        )

        #expect(warning.message.contains("$4.99 per 3 months"))
        // 4.99 x 4 = 19.96 against 29.99.
        #expect(warning.percentCheaper == 33)
    }

    // MARK: - Currency formatting

    @Test(arguments: [
        ("en_US", "USD", Decimal(string: "9.99")!, "$9.99"),
        ("fr_FR", "EUR", Decimal(string: "9.99")!, "9,99\u{00A0}€"),
        ("en_GB", "GBP", Decimal(string: "8.99")!, "£8.99"),
        ("ja_JP", "JPY", Decimal(1500), "¥1,500")
    ])
    func pricesReadInTheStorefrontsOwnCurrencyFormat(
        localeID: String,
        currency: String,
        price: Decimal,
        expected: String
    ) {
        #expect(
            SubscriptionRatePriceFormatter.string(
                price: price,
                currencyCode: currency,
                locale: Locale(identifier: localeID)
            ) == expected
        )
    }

    @Test
    func aWeeklyPlanIsAnnualisedOnA365DayYear() {
        let weekly = Self.rate("weekly", 0.5, per: RatePeriod(unit: .week, value: 1))

        #expect(weekly.yearlyEquivalent > 26 && weekly.yearlyEquivalent < 26.1)
    }
}
