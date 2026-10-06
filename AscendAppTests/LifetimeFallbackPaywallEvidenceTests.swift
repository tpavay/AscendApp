import RevenueCat
import StoreKit
import StoreKitTest
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// The native fallback paywall, drawn from products StoreKit actually returned rather than from
/// fixture plans: `AscendSubscriptions.storekit` lists the annual subscription with its free trial
/// and the Lifetime non-consumable, a `SKTestSession` serves them, and the same
/// `StoreProduct` -> terms -> plan path the shipped provider runs turns them into the cards.
///
/// So what these assertions read is the copy a climber gets for a real one-time purchase: its
/// price, no trial, no renewal, and a purchase action that does not say subscribe. Photographs are
/// written only when `ASCEND_EVIDENCE_DIR` is set (`RenderedScreen`).
@MainActor
@Suite(.serialized, .hostsAWindow, .usesStoreKitTestSession)
struct LifetimeFallbackPaywallEvidenceTests {
    private static let yearlyID = "ascend_staging_yearly"
    private static let lifetimeID = "ascend_staging_lifetime"

    @Test
    func theFallbackSellsAnnualAndLifetimeWithEachProductsOwnTerms() async throws {
        let session = try Self.makeSession()
        defer { Self.cleanUp(session) }
        let plans = try await Self.plansFromStoreKit()

        let annual = try #require(plans.first)
        let lifetime = try #require(plans.last)
        #expect(plans.map(\.id) == [Self.yearlyID, Self.lifetimeID])
        #expect(annual.localizedPrice == "$29.99")
        #expect(annual.billing == .subscription)
        #expect(annual.billingDescription == "Renews annually")
        #expect(annual.trialDescription == "1 month free")
        #expect(annual.purchaseActionTitle == "Start 1-month free trial")
        #expect(lifetime.title == "Lifetime")
        #expect(lifetime.localizedPrice == "$49.99")
        #expect(lifetime.billing == .oneTime)
        #expect(lifetime.billingDescription == "Pay once. No renewal.")
        #expect(lifetime.trialDescription == nil)
        #expect(lifetime.purchaseActionTitle == "Buy Lifetime")

        let content = AppAccessPaywallPlaceholderView(
            initialPhase: .nativeReady,
            initialPlans: plans,
            initialStatusMessage: AppAccessPaywallCoordinator.plansReadyMessage(for: plans),
            automaticallyStarts: false,
            onDeleteAccount: {},
            onSignOut: {}
        )
        .environment(Self.makeManager())
        .environment(\.colorScheme, .dark)
        .transaction { $0.disablesAnimations = true }

        try await RenderedScreen.host(content) { screen in
            // Annual is selected first, so the purchase action is the annual trial.
            let annualSelected = try await screen.copy { $0.contains("start 1-month free trial") }
            for expected in [
                "choose your ascend plan",
                "choose from annual and lifetime",
                "cancel annual anytime in apple subscriptions",
                "$29.99", "1 month free", "renews annually",
                "$49.99", "pay once. no renewal."
            ] {
                #expect(annualSelected.contains(expected), "Missing \(expected) in: \(annualSelected)")
            }
            #expect(!annualSelected.contains("buy lifetime"))
            try screen.photograph(named: "lifetime-fallback-annual-selected")

            let lifetimeCard = try #require(
                accessibilityElements(under: screen.window).first {
                    $0.accessibilityLabel?.hasPrefix("Lifetime") == true
                }
            )
            let lifetimeLabel = try #require(lifetimeCard.accessibilityLabel)
            #expect(lifetimeLabel == "Lifetime, $49.99, Pay once. No renewal.")
            #expect(!lifetimeLabel.localizedCaseInsensitiveContains("trial"))
            #expect(!lifetimeLabel.localizedCaseInsensitiveContains("renews"))

            try activateAccessibilityElement(in: screen.window) {
                $0.accessibilityLabel == lifetimeLabel
            }
            let lifetimeSelected = try await screen.copy { $0.contains("buy lifetime") }
            #expect(lifetimeSelected.contains("buy lifetime"))
            // The trial is still the annual card's own, but it is no longer what the button buys.
            #expect(!lifetimeSelected.contains("start 1-month free trial"))
            #expect(!lifetimeSelected.contains("subscribe with apple"))
            #expect(
                accessibilityElements(under: screen.window).contains {
                    $0.accessibilityLabel == lifetimeLabel && $0.accessibilityValue == "Selected"
                }
            )
            try screen.photograph(named: "lifetime-fallback-lifetime-selected")
        }
    }

    /// The purchase itself, against the same StoreKit configuration: Lifetime is a non-consumable,
    /// so the transaction it leaves never expires, and a refund is what takes it away.
    @Test
    func buyingLifetimeLeavesATransactionThatNeverExpiresUntilRefunded() async throws {
        let session = try Self.makeSession()
        defer { Self.cleanUp(session) }
        let product = try #require(
            try await Product.products(for: [Self.lifetimeID]).first
        )
        #expect(product.type == .nonConsumable)
        #expect(product.subscription == nil)

        _ = try await session.buyProduct(identifier: Self.lifetimeID)
        let purchase = try #require(
            session.allTransactions().first { $0.productIdentifier == Self.lifetimeID }
        )
        #expect(purchase.expirationDate == nil)
        #expect(purchase.cancelDate == nil)

        try session.refundTransaction(identifier: purchase.identifier)
        let refunded = try #require(
            session.allTransactions().first { $0.identifier == purchase.identifier }
        )
        #expect(refunded.cancelDate != nil)
    }
}

private extension LifetimeFallbackPaywallEvidenceTests {
    /// The shipped path from a store product to a plan card, fed by StoreKit instead of RevenueCat's
    /// offerings call, which needs a configured SDK and a network.
    static func plansFromStoreKit() async throws -> [NativePaywallPlan] {
        let products = try await Product.products(for: [yearlyID, lifetimeID])
        #expect(Set(products.map(\.id)) == [yearlyID, lifetimeID])

        var eligibility: [String: NativeTrialEligibility] = [:]
        for product in products {
            guard let subscription = product.subscription else { continue }
            eligibility[product.id] = await subscription.isEligibleForIntroOffer
                ? .eligible
                : .ineligible
        }

        return NativePaywallPlanMapper.plans(
            from: products.map {
                RevenueCatNativePaywallPlanProvider.productTerms(
                    from: RevenueCat.StoreProduct(sk2Product: $0)
                )
            },
            eligibilityByProductID: eligibility,
            yearlyProductID: yearlyID,
            lifetimeProductID: lifetimeID,
            locale: Locale(identifier: "en_US")
        )
    }

    static func makeSession() throws -> SKTestSession {
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

    static func cleanUp(_ session: SKTestSession) {
        session.resetToDefaultState()
        session.clearTransactions()
    }

    static func makeManager() -> MonetizationManager {
        MonetizationManager(
            entitlementService: EntitlementServiceStub(),
            paywallPresenter: PaywallPresenterSpy(),
            telemetry: makeTestTelemetry(sink: InMemoryTelemetrySink(destination: .analytics))
        )
    }
}
