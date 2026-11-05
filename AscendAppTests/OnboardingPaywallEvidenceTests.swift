import Foundation
import enum SuperwallKit.PurchaseResult
import SwiftUI
import Testing
@testable import AscendApp

/// Screens 13 and 14 on screen: the paywall and the welcome gift at the smallest phone Ascend
/// supports and at an accessibility text size. Photographs are written only when
/// `ASCEND_EVIDENCE_DIR` is set.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct OnboardingPaywallEvidenceTests {
    /// iPhone SE (3rd generation), the smallest phone that runs iOS 26.
    private static let smallestPhone = CGSize(width: 375, height: 667)

    private struct Fixture {
        let model: OnboardingPaywallModel
        let coordinator: OnboardingV3Coordinator
        let ledger: PreAuthPurchaseLedger
    }

    private func fixture(
        startingAt step: OnboardingV3Step,
        trialEligible: Bool = true,
        giftAlreadySeen: Bool = false,
        entitlement: MonetizationEntitlementState = .inactive,
        purchaseResult: PurchaseResult = .cancelled
    ) async -> Fixture {
        let suite = "onboarding-paywall-evidence-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let store = PreAuthOnboardingStore(userDefaults: defaults)
        if giftAlreadySeen {
            store.update { $0.welcomeGiftFirstShownAt = Date() }
        }
        let coordinator = OnboardingV3Coordinator(store: store, startingAt: step)

        let configuration = MonetizationConfiguration(infoDictionary: [
            MonetizationConfiguration.revenueCatYearlyProductIDInfoKey: "yearly",
            MonetizationConfiguration.revenueCatLifetimeProductIDInfoKey: "lifetime",
            MonetizationConfiguration.revenueCatWelcomeProductIDInfoKey: "welcome"
        ])
        let manager = MonetizationManager(
            configuration: configuration,
            entitlementService: EntitlementServiceStub(entitlementState: entitlement),
            paywallPresenter: EvidencePresenter(),
            appAccessReconciler: EvidenceReconciler(),
            userDefaults: UserDefaults(suiteName: "\(suite)-manager")!
        )
        let provider = EvidenceProvider(trialEligible: trialEligible, purchaseResult: purchaseResult)
        let ledger = PreAuthPurchaseLedger(userDefaults: defaults)
        let model = OnboardingPaywallModel(
            provider: provider,
            monetization: manager,
            restoreService: AppAccessRestoreService(entitlementID: "app_access", restorer: { manager }),
            ledger: ledger
        )
        await model.load()
        return Fixture(model: model, coordinator: coordinator, ledger: ledger)
    }

    private let paywallCopy = [
        "never climb a boring minute again",
        "someone to chase",
        "real climbers' best climbs, every climb",
        "proof you're improving",
        "a reason to come back",
        "streaks, monthly events, gear to earn",
        "climbs that go somewhere",
        "yearly",
        "$29.99 billed once a year",
        "$2.49",
        "per month",
        "lifetime",
        "$49.99 once",
        "start climbing",
        "cancel anytime",
        "restore",
        "terms",
        "privacy"
    ]

    @Test
    func thePaywallKeepsThePlansAndTheButtonOnTheFirstScreenOfTheSmallestPhone() async throws {
        let fixture = await fixture(startingAt: .paywall)

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: fixture.coordinator)
                .environment(\.onboardingPaywallModel, fixture.model),
            size: Self.smallestPhone,
            settle: .turns(100)
        ) { screen in
            let copy = try await screen.copy(until: { $0.contains("privacy") })
            for line in [
                "never climb a boring minute again", "someone to chase", "yearly",
                "$29.99 billed once a year", "$2.49", "per month", "lifetime", "$49.99 once",
                "start climbing", "cancel anytime", "restore", "terms", "privacy", "close", "already climbing? sign in"
            ] {
                #expect(copy.contains(line), "missing \(line): \(copy)")
            }
            #expect(!copy.contains("ends in"))
            try screen.photograph(named: "onboarding-v3-paywall-se")
        }
    }

    @Test
    func thePaywallShowsEveryLineOfTheDesignOnAStandardPhone() async throws {
        let fixture = await fixture(startingAt: .paywall)

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: fixture.coordinator)
                .environment(\.onboardingPaywallModel, fixture.model),
            settle: .turns(100)
        ) { screen in
            let copy = try await screen.copy(until: { $0.contains("privacy") })
            for line in paywallCopy {
                #expect(copy.contains(line), "missing \(line): \(copy)")
            }
            try screen.photograph(named: "onboarding-v3-paywall-standard")
        }
    }

    @Test
    func thePaywallReadsAtAnAccessibilityTextSize() async throws {
        let fixture = await fixture(startingAt: .paywall)

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: fixture.coordinator)
                .environment(\.onboardingPaywallModel, fixture.model)
                .environment(\.dynamicTypeSize, .accessibility3),
            settle: .turns(100)
        ) { screen in
            let copy = try await screen.copy()
            #expect(copy.contains("never climb a boring minute again"), "\(copy)")
            #expect(copy.contains("someone to chase"), "\(copy)")
            try screen.photograph(named: "onboarding-v3-paywall-accessibility")
        }
    }

    @Test
    func theClosedGiftAsksForATapAndPromisesNothingItCannotKeep() async throws {
        let fixture = await fixture(startingAt: .exitGift)

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: fixture.coordinator)
                .environment(\.onboardingPaywallModel, fixture.model),
            size: Self.smallestPhone,
            settle: .turns(40)
        ) { screen in
            let copy = try await screen.copy(until: { $0.contains("tap to open") }).replacingOccurrences(of: "\n", with: " ")
            for line in ["before you go", "open your welcome gift", "a better price, just for you", "tap to open"] {
                #expect(copy.contains(line), "missing \(line): \(copy)")
            }
            #expect(!copy.contains("only shows up once"))
            try screen.photograph(named: "onboarding-v3-gift-closed-se")
        }
    }

    @Test
    func theOpenGiftNamesTheTrialOnlyWhenTheAppleIDCanStillTakeIt() async throws {
        for (eligible, expected, forbidden) in [
            (true, ["welcome offer", "$9.99", "$29.99", "plus 7 days free", "your first week", "on us", "then $9.99 a year, locked in", "claim my gift", "free today, then $9.99/year. cancel anytime", "no thanks", "66% off", "terms", "privacy"], ["won't show up again", "ends in"]),
            (false, ["welcome offer", "$9.99 a year", "locked in", "that's 66% off, every year you climb", "claim my gift", "$9.99 today, then every year. cancel anytime", "no thanks"], ["free", "first week", "on us", "won't show up again", "ends in"])
        ] {
            let fixture = await fixture(startingAt: .exitGift, trialEligible: eligible, giftAlreadySeen: true)

            try await RenderedScreen.host(
                OnboardingV3FlowView(coordinator: fixture.coordinator)
                    .environment(\.onboardingPaywallModel, fixture.model),
                size: Self.smallestPhone,
                settle: .turns(120)
            ) { screen in
                let copy = try await screen.copy(until: { $0.contains("no thanks") })
                for line in expected {
                    #expect(copy.contains(line), "eligible \(eligible), missing \(line): \(copy)")
                }
                for line in forbidden {
                    #expect(!copy.contains(line), "eligible \(eligible), found \(line): \(copy)")
                }
                try screen.photograph(named: "onboarding-v3-gift-open-\(eligible ? "trial" : "no-trial")-se")
            }
        }
    }

    @Test
    func theOpenGiftStaysReachableAtAnAccessibilityTextSize() async throws {
        let fixture = await fixture(startingAt: .exitGift, giftAlreadySeen: true)

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: fixture.coordinator)
                .environment(\.onboardingPaywallModel, fixture.model)
                .environment(\.dynamicTypeSize, .accessibility3),
            settle: .turns(120)
        ) { screen in
            let copy = try await screen.copy()
            for line in ["welcome offer", "$9.99"] {
                #expect(copy.contains(line), "missing \(line): \(copy)")
            }
            try screen.photograph(named: "onboarding-v3-gift-open-accessibility")
        }
    }

    @Test
    func anUnconfirmedPurchaseOffersACheckInsteadOfAnotherPurchaseOnBothScreens() async throws {
        let paywall = await fixture(startingAt: .paywall, purchaseResult: .pending)
        _ = await paywall.model.purchaseSelectedPlan()

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: paywall.coordinator)
                .environment(\.onboardingPaywallModel, paywall.model),
            settle: .turns(100)
        ) { screen in
            let copy = try await screen.copy(until: { $0.contains("check access") })
            #expect(copy.contains("do not purchase again"), "\(copy)")
            #expect(!copy.contains("start climbing"), "\(copy)")
        }

        let gift = await fixture(startingAt: .exitGift, giftAlreadySeen: true, purchaseResult: .pending)
        _ = await gift.model.claimGift()

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: gift.coordinator)
                .environment(\.onboardingPaywallModel, gift.model),
            size: Self.smallestPhone,
            settle: .turns(120)
        ) { screen in
            let copy = try await screen.copy(until: { $0.contains("check access") })
            #expect(copy.contains("do not purchase again"), "\(copy)")
            #expect(!copy.contains("claim my gift"), "\(copy)")
        }
    }

    @Test
    func aClimberWhoAlreadyHoldsAccessIsRememberedAsThePaywallMovesThemOn() async throws {
        let fixture = await fixture(startingAt: .paywall, entitlement: .active(["app_access"]))
        let coordinator = fixture.coordinator

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: coordinator)
                .environment(\.onboardingPaywallModel, fixture.model),
            settle: .until { _ in coordinator.step == .auth }
        ) { _ in
            #expect(coordinator.step == .auth)
            #expect(fixture.ledger.resumeStep == .auth)
        }
    }

    /// Reads the box on the first frame after it opens. The body waits 0.35 s before it sinks, so a
    /// box that is really animating is still there; a box that was replaced is already gone.
    @Test
    func openingTheBoxAnimatesTheBoxThatWasThere() async throws {
        let driver = GiftBoxDriver()
        let size = CGSize(width: 300, height: 300)
        // The body's left panel, clear of the ribbon: the box is 180 by 190, centred.
        let bodyPanel = CGPoint(x: (size.width - 180) / 2 + 40, y: (size.height + 190) / 2 - 50)

        try await RenderedScreen.host(GiftBoxHarness(driver: driver), size: size) { screen in
            #expect(!(try screen.color(at: bodyPanel).isNearBlack), "the closed box should show its body")

            driver.isOpen = true
            try await screen.settle(.turns(1))
            #expect(!(try screen.color(at: bodyPanel).isNearBlack), "the box vanished instead of animating")

            try await Task.sleep(for: .seconds(1.2))
            #expect(try screen.color(at: bodyPanel).isNearBlack, "the opened box should be gone")
        }
    }
}

@MainActor
@Observable
private final class GiftBoxDriver {
    var isOpen = false
}

private struct GiftBoxHarness: View {
    let driver: GiftBoxDriver

    var body: some View {
        ZStack {
            Color.black
            WelcomeGiftBox(isOpen: driver.isOpen)
        }
    }
}

@MainActor
private final class EvidenceProvider: PreAuthPaywallPlanProviding {
    let trialEligible: Bool
    let purchaseResult: PurchaseResult

    init(trialEligible: Bool, purchaseResult: PurchaseResult) {
        self.trialEligible = trialEligible
        self.purchaseResult = purchaseResult
    }

    func loadPlans() async throws -> [NativePaywallPlan] { try await loadPreAuthPlans() }

    func loadPreAuthPlans() async throws -> [NativePaywallPlan] {
        [
            NativePaywallPlan(
                id: "yearly", title: "Annual", localizedPrice: "$29.99",
                billingDescription: "Renews annually", trialDescription: nil,
                price: 29.99, localizedPricePerMonth: "$2.49"
            ),
            NativePaywallPlan(
                id: "lifetime", title: "Lifetime", localizedPrice: "$49.99", billing: .oneTime,
                billingDescription: "Pay once. No renewal.", trialDescription: nil, price: 49.99
            ),
            NativePaywallPlan(
                id: "welcome", title: "Annual", localizedPrice: "$9.99",
                billingDescription: "Renews annually",
                trialDescription: trialEligible ? "7 days free" : nil,
                price: 9.99,
                freeTrialPeriod: trialEligible ? NativeSubscriptionPeriod(value: 1, unit: .week) : nil
            )
        ]
    }

    func purchase(planID: String) async -> PurchaseResult { purchaseResult }
}

@MainActor
private final class EvidencePresenter: PaywallPresenting {
    var isConfigured = false
    func configure(configuration: MonetizationConfiguration) {}
    func identify(userId: String) {}
    func resetIdentity() {}
    func register(
        placement: SuperwallPlacement,
        params: [String: Any]?,
        onOutcome: @escaping @MainActor (PaywallPresentationOutcome) -> Void
    ) {}
}

@MainActor
private final class EvidenceReconciler: AppAccessReconciling {
    func reconcileAppAccess(force: Bool) async {}
}
