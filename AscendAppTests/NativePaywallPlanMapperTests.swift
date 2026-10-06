import Foundation
import Testing
@testable import AscendApp

struct NativePaywallPlanMapperTests {
    private let annualID = "ascend_staging_yearly"
    private let lifetimeID = "ascend_staging_lifetime"

    @Test(arguments: [
        NativeTrialEligibility.ineligible,
        NativeTrialEligibility.unknown
    ])
    func annualTrialIsHiddenUnlessRevenueCatSaysEligible(
        eligibility: NativeTrialEligibility
    ) throws {
        let annual = try #require(plans(annualEligibility: eligibility).first)

        #expect(annual.trialDescription == nil)
        #expect(annual.billing == .subscription)
        #expect(annual.billingDescription == "Renews annually")
        #expect(annual.purchaseActionTitle == "Subscribe with Apple")
    }

    @Test(arguments: [
        (NativeSubscriptionPeriod(value: 1, unit: .month), "1 month free", "Start 1-month free trial"),
        (NativeSubscriptionPeriod(value: 1, unit: .week), "7 days free", "Start 7-day free trial")
    ])
    func eligibleAnnualTrialCopyIsReadFromTheProductsOwnOffer(
        trial: NativeSubscriptionPeriod,
        description: String,
        action: String
    ) throws {
        let annual = try #require(
            plans(annualEligibility: .eligible, annualTrial: trial).first
        )

        #expect(annual.trialDescription == description)
        #expect(annual.purchaseActionTitle == action)
    }

    @Test
    func annualWithNoIntroductoryOfferNeverClaimsATrialEvenWhenEligible() throws {
        let annual = try #require(
            plans(annualEligibility: .eligible, annualTrial: nil).first
        )

        #expect(annual.trialDescription == nil)
        #expect(annual.purchaseActionTitle == "Subscribe with Apple")
    }

    @Test
    func lifetimeIsAOneTimePurchaseWithNoTrialAndNoRenewal() throws {
        let lifetime = try #require(
            plans(annualEligibility: .eligible).first { $0.id == lifetimeID }
        )

        #expect(lifetime.title == "Lifetime")
        #expect(lifetime.localizedPrice == "$49.99")
        #expect(lifetime.billing == .oneTime)
        #expect(lifetime.billingDescription == "Pay once. No renewal.")
        #expect(lifetime.trialDescription == nil)
        #expect(lifetime.trialActionDescription == nil)
        #expect(lifetime.purchaseActionTitle == "Buy Lifetime")
    }

    @Test
    func aOneTimePurchaseNeverBorrowsTrialOrRenewalTermsTheProviderReportsBesideIt() throws {
        // The card is written from what the product is, so a provider answer that claims an
        // introductory offer or a period for a non-consumable cannot put either on screen.
        let mapped = NativePaywallPlanMapper.plans(
            from: [
                NativePaywallProductTerms(
                    productID: lifetimeID,
                    localizedPrice: "$49.99",
                    billing: .oneTime,
                    renewalPeriod: NativeSubscriptionPeriod(value: 1, unit: .year),
                    freeTrialPeriod: NativeSubscriptionPeriod(value: 1, unit: .month)
                )
            ],
            eligibilityByProductID: [lifetimeID: .eligible],
            yearlyProductID: annualID,
            lifetimeProductID: lifetimeID
        )
        let lifetime = try #require(mapped.first)

        #expect(lifetime.billingDescription == "Pay once. No renewal.")
        #expect(lifetime.trialDescription == nil)
        #expect(lifetime.purchaseActionTitle == "Buy Lifetime")
    }

    @Test
    func plansAreListedAnnualFirstWhateverOrderTheStoreAnswersIn() {
        let mapped = NativePaywallPlanMapper.plans(
            from: [lifetimeTerms, annualTerms(trial: nil)],
            eligibilityByProductID: [:],
            yearlyProductID: annualID,
            lifetimeProductID: lifetimeID
        )

        #expect(mapped.map(\.id) == [annualID, lifetimeID])
    }

    @Test
    func aProductTheStoreDidNotReturnIsLeftOffRatherThanInvented() {
        // Lifetime is unavailable until Apple approves it, and the fallback then has to sell the
        // annual plan alone instead of drawing a card nothing can buy.
        let annualOnly = NativePaywallPlanMapper.plans(
            from: [annualTerms(trial: nil)],
            eligibilityByProductID: [:],
            yearlyProductID: annualID,
            lifetimeProductID: lifetimeID
        )
        let lifetimeOnly = NativePaywallPlanMapper.plans(
            from: [lifetimeTerms],
            eligibilityByProductID: [:],
            yearlyProductID: annualID,
            lifetimeProductID: lifetimeID
        )

        #expect(annualOnly.map(\.id) == [annualID])
        #expect(lifetimeOnly.map(\.id) == [lifetimeID])
        #expect(lifetimeOnly.first?.title == "Lifetime")
    }

    @Test
    func localizedTitlesAndMultiPeriodPluralsComeFromFoundationAndResources() throws {
        let plans = NativePaywallPlanMapper.plans(
            from: [
                NativePaywallProductTerms(
                    productID: annualID,
                    localizedPrice: "29,99 €",
                    renewalPeriod: NativeSubscriptionPeriod(value: 3, unit: .month),
                    freeTrialPeriod: NativeSubscriptionPeriod(value: 2, unit: .week)
                ),
                lifetimeTerms
            ],
            eligibilityByProductID: [annualID: .eligible, lifetimeID: .ineligible],
            yearlyProductID: annualID,
            lifetimeProductID: lifetimeID,
            locale: Locale(identifier: "fr_FR"),
            bundle: .main
        )
        let annual = try #require(plans.first)
        let lifetime = try #require(plans.last)

        #expect(annual.title == "Annuel")
        #expect(annual.billingDescription == "Renouvelé tous les 3\u{00A0}mois")
        #expect(annual.trialDescription == "Essai gratuit de 2\u{00A0}semaines")
        #expect(annual.purchaseActionTitle == "Commencer l’essai gratuit de 2\u{00A0}semaines")
        #expect(lifetime.title == "À vie")
        #expect(lifetime.billingDescription == "Paiement unique. Sans renouvellement.")
    }

    private func plans(
        annualEligibility: NativeTrialEligibility,
        annualTrial: NativeSubscriptionPeriod? = NativeSubscriptionPeriod(value: 1, unit: .month)
    ) -> [NativePaywallPlan] {
        NativePaywallPlanMapper.plans(
            from: [annualTerms(trial: annualTrial), lifetimeTerms],
            eligibilityByProductID: [
                annualID: annualEligibility,
                lifetimeID: .eligible
            ],
            yearlyProductID: annualID,
            lifetimeProductID: lifetimeID
        )
    }

    private func annualTerms(trial: NativeSubscriptionPeriod?) -> NativePaywallProductTerms {
        NativePaywallProductTerms(
            productID: annualID,
            localizedPrice: "$29.99",
            renewalPeriod: NativeSubscriptionPeriod(value: 1, unit: .year),
            freeTrialPeriod: trial
        )
    }

    private var lifetimeTerms: NativePaywallProductTerms {
        NativePaywallProductTerms(
            productID: lifetimeID,
            localizedPrice: "$49.99",
            billing: .oneTime,
            renewalPeriod: nil,
            freeTrialPeriod: nil
        )
    }
}
