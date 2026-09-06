import Foundation
import Testing
@testable import AscendApp

struct NativeSubscriptionPlanMapperTests {
    private let annualID = "ascend_staging_yearly"
    private let monthlyID = "ascend_staging_monthly"

    @Test(arguments: [
        NativeTrialEligibility.ineligible,
        NativeTrialEligibility.unknown
    ])
    func annualTrialIsHiddenUnlessRevenueCatSaysEligible(
        eligibility: NativeTrialEligibility
    ) throws {
        let annual = try #require(plans(annualEligibility: eligibility).first)

        #expect(annual.trialDescription == nil)
        #expect(annual.renewalDescription == "Renews annually")
        #expect(annual.purchaseActionTitle == "Subscribe with Apple")
    }

    @Test
    func eligibleAnnualTrialIncludesLocalizedPostTrialPriceAndPeriod() throws {
        let annual = try #require(plans(annualEligibility: .eligible).first)

        #expect(
            annual.trialDescription ==
                "7 days free"
        )
        #expect(annual.purchaseActionTitle == "Start 7-day free trial")
    }

    @Test
    func monthlyNeverClaimsATrialEvenIfProviderEligibilityIsEligible() throws {
        let monthly = try #require(
            plans(annualEligibility: .eligible).first { $0.id == monthlyID }
        )

        #expect(monthly.trialDescription == nil)
        #expect(monthly.renewalDescription == "Renews monthly")
        #expect(monthly.purchaseActionTitle == "Subscribe with Apple")
    }

    @Test
    func missingExpectedPackageReturnsTruthfulPartialCatalog() {
        let mapped = NativeSubscriptionPlanMapper.plans(
            from: [monthlyTerms],
            eligibilityByProductID: [monthlyID: .eligible],
            yearlyProductID: annualID,
            monthlyProductID: monthlyID
        )

        #expect(mapped.map(\.id) == [monthlyID])
        #expect(mapped.first?.title == "Monthly")
        #expect(mapped.first?.trialDescription == nil)
    }

    @Test
    func localizedTitlesAndMultiPeriodPluralsComeFromFoundationAndResources() throws {
        let plans = NativeSubscriptionPlanMapper.plans(
            from: [
                NativeSubscriptionProductTerms(
                    productID: annualID,
                    localizedPrice: "49,99 €",
                    renewalPeriod: NativeSubscriptionPeriod(value: 3, unit: .month),
                    freeTrialPeriod: NativeSubscriptionPeriod(value: 2, unit: .week)
                ),
                monthlyTerms
            ],
            eligibilityByProductID: [annualID: .eligible, monthlyID: .ineligible],
            yearlyProductID: annualID,
            monthlyProductID: monthlyID,
            locale: Locale(identifier: "fr_FR"),
            bundle: .main
        )
        let annual = try #require(plans.first)

        #expect(annual.title == "Annuel")
        #expect(annual.renewalDescription == "Renouvelé tous les 3\u{00A0}mois")
        #expect(annual.trialDescription == "Essai gratuit de 2\u{00A0}semaines")
        #expect(annual.purchaseActionTitle == "Commencer l’essai gratuit de 2\u{00A0}semaines")
    }

    private func plans(
        annualEligibility: NativeTrialEligibility
    ) -> [NativeSubscriptionPlan] {
        NativeSubscriptionPlanMapper.plans(
            from: [annualTerms, monthlyTerms],
            eligibilityByProductID: [
                annualID: annualEligibility,
                monthlyID: .eligible
            ],
            yearlyProductID: annualID,
            monthlyProductID: monthlyID
        )
    }

    private var annualTerms: NativeSubscriptionProductTerms {
        NativeSubscriptionProductTerms(
            productID: annualID,
            localizedPrice: "$49.99",
            renewalPeriod: NativeSubscriptionPeriod(value: 1, unit: .year),
            freeTrialPeriod: NativeSubscriptionPeriod(value: 1, unit: .week)
        )
    }

    private var monthlyTerms: NativeSubscriptionProductTerms {
        NativeSubscriptionProductTerms(
            productID: monthlyID,
            localizedPrice: "$9.99",
            renewalPeriod: NativeSubscriptionPeriod(value: 1, unit: .month),
            freeTrialPeriod: NativeSubscriptionPeriod(value: 1, unit: .week)
        )
    }
}
