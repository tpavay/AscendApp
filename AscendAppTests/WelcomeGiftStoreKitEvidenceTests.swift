import RevenueCat
import StoreKit
import StoreKitTest
import Testing
@testable import AscendApp

/// The welcome gift drawn from what StoreKit actually returns: `AscendSubscriptions.storekit` lists
/// the welcome product beside the yearly plan, a `SKTestSession` serves them, and the path the
/// shipped provider runs turns them into the words on the voucher.
@MainActor
@Suite(.serialized, .usesStoreKitTestSession)
struct WelcomeGiftStoreKitEvidenceTests {
    private static let yearlyID = "ascend_staging_yearly"
    private static let lifetimeID = "ascend_staging_lifetime"
    private static let welcomeID = "ascend_staging_yearly_welcome"

    private static func makeSession() throws -> SKTestSession {
        let configurationURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "AscendApp")
            .appending(path: "Configuration")
            .appending(path: "AscendSubscriptions.storekit")
        let session = try SKTestSession(contentsOf: configurationURL)
        session.disableDialogs = true
        session.resetToDefaultState()
        session.clearTransactions()
        return session
    }

    private static func cleanUp(_ session: SKTestSession) {
        session.resetToDefaultState()
        session.clearTransactions()
    }

    private func plans() async throws -> [NativePaywallPlan] {
        let products = try await Product.products(for: [Self.yearlyID, Self.lifetimeID, Self.welcomeID])

        var eligibility: [String: NativeTrialEligibility] = [:]
        for product in products {
            guard let subscription = product.subscription else { continue }
            eligibility[product.id] = await subscription.isEligibleForIntroOffer ? .eligible : .ineligible
        }

        return NativePaywallPlanMapper.plans(
            from: products.map {
                RevenueCatNativePaywallPlanProvider.productTerms(from: RevenueCat.StoreProduct(sk2Product: $0))
            },
            eligibilityByProductID: eligibility,
            yearlyProductID: Self.yearlyID,
            lifetimeProductID: Self.lifetimeID,
            welcomeProductID: Self.welcomeID,
            locale: Locale(identifier: "en_US")
        )
    }

    private func offer(from plans: [NativePaywallPlan]) throws -> WelcomeGiftOffer {
        let welcome = try #require(plans.first { $0.id == Self.welcomeID })
        let yearly = try #require(plans.first { $0.id == Self.yearlyID })
        return try #require(WelcomeGiftOffer(welcome: welcome, regular: yearly))
    }

    @Test
    func aFreshAppleIDReadsTheStoresPricesAndTheSevenDayTrial() async throws {
        let session = try Self.makeSession()
        defer { Self.cleanUp(session) }

        let offer = try offer(from: try await plans())

        #expect(offer.price == "$9.99")
        #expect(offer.regularPrice == "$29.99")
        #expect(offer.percentOff == 66)

        let copy = WelcomeGiftCopy(offer)
        #expect(copy.trialLine == "PLUS 7 DAYS FREE")
        #expect(copy.finePrint == "Free today, then $9.99/year. Cancel anytime.")
        #expect(copy.stamp == "66%")
    }

    /// The two products share a subscription group, so an Apple ID takes one trial between them. An
    /// Apple ID that already took the yearly trial must not be promised another on the gift.
    @Test
    func anAppleIDThatTookTheYearlyTrialIsPromisedNoTrialOnTheGift() async throws {
        let session = try Self.makeSession()
        defer { Self.cleanUp(session) }

        try await session.buyProduct(identifier: Self.yearlyID)
        // StoreKit reports eligibility from its own transaction history, which trails the purchase.
        var plans = try await plans()
        for _ in 0..<50 where plans.first(where: { $0.id == Self.welcomeID })?.freeTrialPeriod != nil {
            try await Task.sleep(for: .milliseconds(100))
            plans = try await self.plans()
        }

        let offer = try offer(from: plans)
        #expect(offer.freeTrial == nil)

        let copy = WelcomeGiftCopy(offer)
        #expect(copy.trialLine == nil)
        #expect(copy.finePrint == "$9.99 today, then every year. Cancel anytime.")
        #expect(copy.subline == "That's 66% off, every year you climb.")
    }
}
