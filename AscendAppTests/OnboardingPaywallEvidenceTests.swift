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
        purchaseResult: PurchaseResult = .cancelled,
        restoredState: MonetizationEntitlementState? = nil,
        pending: PreAuthPendingPurchase? = nil,
        storeHasPlans: Bool = true,
        fadeNeverEnds: Bool = false
    ) async -> Fixture {
        let suite = "onboarding-paywall-evidence-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let store = PreAuthOnboardingStore(userDefaults: defaults)
        if giftAlreadySeen {
            store.update { $0.welcomeGiftFirstShownAt = Date() }
        }
        let stoppedClock = ContinuousClock.now
        let coordinator = OnboardingV3Coordinator(
            store: store,
            startingAt: step,
            now: { fadeNeverEnds ? stoppedClock : .now }
        )

        let configuration = MonetizationConfiguration(infoDictionary: [
            MonetizationConfiguration.revenueCatYearlyProductIDInfoKey: "yearly",
            MonetizationConfiguration.revenueCatLifetimeProductIDInfoKey: "lifetime",
            MonetizationConfiguration.revenueCatWelcomeProductIDInfoKey: "welcome"
        ])
        let service = EntitlementServiceStub(entitlementState: entitlement)
        service.restoredState = restoredState
        let manager = MonetizationManager(
            configuration: configuration,
            entitlementService: service,
            paywallPresenter: EvidencePresenter(),
            appAccessReconciler: EvidenceReconciler(),
            userDefaults: UserDefaults(suiteName: "\(suite)-manager")!
        )
        let provider = EvidenceProvider(
            trialEligible: trialEligible,
            purchaseResult: purchaseResult,
            storeHasPlans: storeHasPlans
        )
        let ledger = PreAuthPurchaseLedger(userDefaults: defaults)
        if let pending { ledger.markPurchasePending(pending) }
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
                .environment(\.onboardingPaywallModel, fixture.model)
                .environment(AuthenticationViewModel()),
            size: Self.smallestPhone,
            settle: .turns(100)
        ) { screen in
            let copy = try await screen.copy(until: { $0.contains("privacy") })
            for line in [
                "never climb a boring minute again", "someone to chase", "yearly",
                "$29.99 billed once a year", "$2.49", "per month", "lifetime", "$49.99 once",
                "start climbing", "cancel anytime", "restore", "terms", "privacy", "close",
                OnboardingPaywallScreen.signInExitTitle.lowercased()
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
                .environment(\.onboardingPaywallModel, fixture.model)
                .environment(AuthenticationViewModel()),
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
                .environment(AuthenticationViewModel())
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
                .environment(\.onboardingPaywallModel, fixture.model)
                .environment(AuthenticationViewModel()),
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

    private func closedGiftFrames(on screen: HostedScreen) async throws -> (subline: CGRect, box: CGRect, tap: CGRect) {
        let elements = try await screen.elements(until: { found in
            found.contains { $0.accessibilityLabel == "Tap to open" }
        })
        func frame(_ label: String) throws -> CGRect {
            try #require(elements.first { $0.accessibilityLabel == label }).accessibilityFrame
        }
        return (
            try frame("A better price, just for you."),
            try frame("Open your gift"),
            try frame("Tap to open")
        )
    }

    @Test(arguments: [CGSize(width: 375, height: 667), CGSize(width: 402, height: 874)])
    func theClosedGiftKeepsItsWordsClearOfTheBoxAtAnAccessibilityTextSize(size: CGSize) async throws {
        let fixture = await fixture(startingAt: .exitGift)

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: fixture.coordinator)
                .environment(\.onboardingPaywallModel, fixture.model)
                .environment(AuthenticationViewModel())
                .environment(\.dynamicTypeSize, .accessibility3),
            size: size,
            settle: .turns(40)
        ) { screen in
            let frames = try await closedGiftFrames(on: screen)
            #expect(frames.subline.maxY <= frames.box.minY, "the box covers the header: \(frames)")
            #expect(frames.box.maxY <= frames.tap.minY, "the box covers the prompt: \(frames)")
        }
    }

    @Test(arguments: [CGSize(width: 375, height: 667), CGSize(width: 402, height: 874)])
    func theClosedGiftCentresTheBoxTwentyPointsLowAtTheDefaultTextSize(size: CGSize) async throws {
        let fixture = await fixture(startingAt: .exitGift)

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: fixture.coordinator)
                .environment(\.onboardingPaywallModel, fixture.model)
                .environment(AuthenticationViewModel()),
            size: size,
            settle: .turns(40)
        ) { screen in
            let frames = try await closedGiftFrames(on: screen)
            let insets = screen.root.safeAreaInsets
            let safeMidY = insets.top + (screen.bounds.height - insets.top - insets.bottom) / 2
            #expect(abs(frames.box.midY - (safeMidY + 20)) <= 4, "\(frames) around \(safeMidY)")
            #expect(frames.subline.maxY <= frames.box.minY, "\(frames)")
        }
    }

    @Test
    func theOpenGiftNamesTheTrialOnlyWhenTheAppleIDCanStillTakeIt() async throws {
        for (eligible, expected, forbidden) in [
            (true, ["welcome offer", "$9.99", "$29.99", "plus 7 days free", "your first week", "on us", "then $9.99 a year, locked in", "claim my gift", "free today, then $9.99/year. cancel anytime", "no thanks", "66% off", "terms", "privacy"], ["won't show up again", "ends in", "before you go", "tap to open"]),
            (false, ["welcome offer", "$9.99 a year", "locked in", "that's 66% off, every year you climb", "claim my gift", "$9.99 today, then every year. cancel anytime", "no thanks"], ["free", "first week", "on us", "won't show up again", "ends in", "before you go", "tap to open"])
        ] {
            let fixture = await fixture(startingAt: .exitGift, trialEligible: eligible, giftAlreadySeen: true)

            try await RenderedScreen.host(
                OnboardingV3FlowView(coordinator: fixture.coordinator)
                    .environment(\.onboardingPaywallModel, fixture.model)
                    .environment(AuthenticationViewModel()),
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
                .environment(AuthenticationViewModel())
                .environment(\.dynamicTypeSize, .accessibility3),
            settle: .turns(120)
        ) { screen in
            let copy = try await screen.copy()
            for line in ["welcome offer", "$9.99"] {
                #expect(copy.contains(line), "missing \(line): \(copy)")
            }
            let drawn = try await screen.recognizedText(scale: 3)
            #expect(drawn.contains("66%"), "the stamp should draw its whole figure: \(drawn)")
            try screen.photograph(named: "onboarding-v3-gift-open-accessibility")
        }
    }

    @Test
    func anUnconfirmedPurchaseOffersACheckInsteadOfAnotherPurchaseOnBothScreens() async throws {
        let paywall = await fixture(startingAt: .paywall, purchaseResult: .pending)
        _ = await paywall.model.purchaseSelectedPlan()

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: paywall.coordinator)
                .environment(\.onboardingPaywallModel, paywall.model)
                .environment(AuthenticationViewModel()),
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
                .environment(\.onboardingPaywallModel, gift.model)
                .environment(AuthenticationViewModel()),
            size: Self.smallestPhone,
            settle: .turns(120)
        ) { screen in
            let copy = try await screen.copy(until: { $0.contains("check access") })
            #expect(copy.contains("do not purchase again"), "\(copy)")
            #expect(!copy.contains("claim my gift"), "\(copy)")
        }
    }

    @Test
    func aRelaunchWhilePendingReopensThePaywallWithNoWayToBuy() async throws {
        let fixture = await fixture(
            startingAt: .paywall,
            pending: PreAuthPendingPurchase(productID: "yearly", hold: .unconfirmedCharge)
        )

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: fixture.coordinator)
                .environment(\.onboardingPaywallModel, fixture.model)
                .environment(AuthenticationViewModel()),
            settle: .turns(100)
        ) { screen in
            let copy = try await screen.copy(until: { $0.contains("check access") })
            #expect(copy.contains("do not purchase again"), "\(copy)")
            #expect(!copy.contains("start climbing"), "\(copy)")
        }
    }

    private func expectThePaywallOffersNoPurchase(on screen: HostedScreen) async throws {
        let copy = try await screen.copy(until: { $0.contains("check access") })
        #expect(copy.contains("do not purchase again"), "\(copy)")
        #expect(!copy.contains("start climbing"), "\(copy)")

        let elements = try await screen.elements()
        let lifetimeCard = try #require(elements.first { $0.accessibilityLabel?.hasPrefix("Lifetime") == true })
        #expect(lifetimeCard.accessibilityTraits.contains(.notEnabled))
    }

    @Test
    func anUnconfirmedChargeStaysLockedAfterTheSignInExitBackAndARelaunch() async throws {
        let charge = PreAuthPendingPurchase(productID: "yearly", hold: .unconfirmedCharge)
        let fixture = await fixture(startingAt: .paywall, pending: charge)
        let coordinator = fixture.coordinator

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: coordinator)
                .environment(\.onboardingPaywallModel, fixture.model)
                .environment(AuthenticationViewModel()),
            settle: .turns(40)
        ) { screen in
            try activateAccessibilityElement(labelled: OnboardingPaywallScreen.signInExitTitle, in: screen.root)
            try await screen.settle(.until { _ in coordinator.step == .auth })
            #expect(coordinator.returningSignInRequested)
            #expect(fixture.ledger.progress().pendingPurchase == charge)

            coordinator.back()
            try await screen.settle(.until { _ in coordinator.step == .paywall })
            try await screen.settle(.turns(20))
            try await expectThePaywallOffersNoPurchase(on: screen)
        }

        #expect(fixture.ledger.resumeStep == .paywall)
        let relaunched = await self.fixture(
            startingAt: .paywall,
            pending: fixture.ledger.progress().pendingPurchase
        )

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: relaunched.coordinator)
                .environment(\.onboardingPaywallModel, relaunched.model)
                .environment(AuthenticationViewModel()),
            settle: .turns(40)
        ) { screen in
            try await expectThePaywallOffersNoPurchase(on: screen)
        }
    }

    @Test
    func theSignInExitLetsGoOfAnAskToBuy() async throws {
        let fixture = await fixture(
            startingAt: .paywall,
            pending: PreAuthPendingPurchase(productID: "yearly", hold: .askToBuy)
        )
        let coordinator = fixture.coordinator

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: coordinator)
                .environment(\.onboardingPaywallModel, fixture.model)
                .environment(AuthenticationViewModel()),
            settle: .turns(40)
        ) { screen in
            try activateAccessibilityElement(labelled: OnboardingPaywallScreen.signInExitTitle, in: screen.root)
            try await screen.settle(.until { _ in coordinator.step == .auth })
            #expect(coordinator.returningSignInRequested)
            #expect(fixture.ledger.progress().pendingPurchase == nil)

            coordinator.back()
            try await screen.settle(.until { _ in coordinator.step == .paywall })
            let copy = try await screen.copy(until: { $0.contains("start climbing") })
            #expect(!copy.contains("check access"), "\(copy)")
        }
    }

    @Test
    func goingBackToTheGiftWhileHoldingAccessOffersNoSale() async throws {
        let fixture = await fixture(
            startingAt: .paywall,
            giftAlreadySeen: true,
            purchaseResult: .purchased
        )
        let coordinator = fixture.coordinator
        coordinator.go(to: .exitGift)

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: coordinator)
                .environment(\.onboardingPaywallModel, fixture.model)
                .environment(AuthenticationViewModel()),
            settle: .turns(40)
        ) { screen in
            #expect(await fixture.model.claimGift() == .purchased(startedTrial: true))
            try await screen.settle(.until { _ in coordinator.step == .auth })

            // Back while the gift is still fading out, which is the arrival that once revived it.
            coordinator.back()
            #expect(coordinator.step == .exitGift)
            try await screen.settle(.until { _ in coordinator.step == .auth })
            try await screen.settle(.turns(20))

            let copy = try await screen.copy()
            #expect(!copy.contains("claim my gift"), "\(copy)")
        }
    }

    @Test
    func restoringAnUnconfirmedTrialCarriesTheTrialIntoTheAnswers() async throws {
        let fixture = await fixture(
            startingAt: .paywall,
            purchaseResult: .failed(RevenueCatPurchaseControllerError.entitlementUnconfirmed),
            restoredState: .active(["app_access"])
        )
        _ = await fixture.model.claimGift()
        let coordinator = fixture.coordinator

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: coordinator)
                .environment(\.onboardingPaywallModel, fixture.model)
                .environment(AuthenticationViewModel()),
            settle: .turns(40)
        ) { screen in
            try activateAccessibilityElement(labelled: "Restore", in: screen.root)
            try await screen.settle(.until { _ in coordinator.step == .auth })
            #expect(coordinator.answers.trialStarted)
            #expect(fixture.ledger.progress().purchase?.startedTrial == true)
        }
    }

    @Test
    func aNoticeFromThePaywallDoesNotFollowTheClimberOntoTheGift() async throws {
        let fixture = await fixture(startingAt: .exitGift, giftAlreadySeen: true)
        _ = await fixture.model.restore()
        #expect(fixture.model.notice == .nothingToRestore)

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: fixture.coordinator)
                .environment(\.onboardingPaywallModel, fixture.model)
                .environment(AuthenticationViewModel()),
            size: Self.smallestPhone,
            settle: .turns(120)
        ) { screen in
            let copy = try await screen.copy(until: { $0.contains("no thanks") })
            #expect(!copy.contains("no active ascend purchase"), "\(copy)")
        }
    }

    @Test
    func aClimberWhoAlreadyHoldsAccessIsRememberedAsThePaywallMovesThemOn() async throws {
        let fixture = await fixture(startingAt: .paywall, entitlement: .active(["app_access"]))
        let coordinator = fixture.coordinator

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: coordinator)
                .environment(\.onboardingPaywallModel, fixture.model)
                .environment(AuthenticationViewModel()),
            settle: .until { _ in coordinator.step == .auth }
        ) { _ in
            #expect(coordinator.step == .auth)
            #expect(fixture.ledger.resumeStep == .auth)
        }
    }

    /// The clock is stopped so the arrival is always inside the fade, where a second tap is dropped.
    @Test(arguments: [OnboardingV3Step.paywall, .exitGift])
    func arrivingHoldingAccessMovesOnEvenInsideTheFade(step: OnboardingV3Step) async throws {
        let fixture = await fixture(
            startingAt: .welcome,
            entitlement: .active(["app_access"]),
            fadeNeverEnds: true
        )
        let coordinator = fixture.coordinator

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: coordinator)
                .environment(\.onboardingPaywallModel, fixture.model)
                .environment(AuthenticationViewModel()),
            settle: .turns(20)
        ) { screen in
            coordinator.go(to: step)
            try await screen.settle(.until { _ in coordinator.step == .auth })
            #expect(coordinator.step == .auth)
        }
    }

    @Test
    func theKillSwitchSkipsThePaywallEvenInsideTheFade() async throws {
        let shippedFlags = RemoteFeatureFlagStore.shared.snapshot
        RemoteFeatureFlagStore.shared.apply(.resolving(remoteValues: [RemoteFeatureFlag.preAuthPaywall.key: false]))
        defer { RemoteFeatureFlagStore.shared.apply(shippedFlags) }

        let fixture = await fixture(startingAt: .welcome, fadeNeverEnds: true)
        let coordinator = fixture.coordinator

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: coordinator)
                .environment(\.onboardingPaywallModel, fixture.model)
                .environment(AuthenticationViewModel()),
            settle: .turns(20)
        ) { screen in
            coordinator.go(to: .paywall)
            try await screen.settle(.until { _ in coordinator.step == .auth })
            #expect(coordinator.step == .auth)
        }
    }

    /// Rendered glyphs, because the accessibility tree holds a truncated line's whole string. The
    /// gift's footer shares its stack with a spacer, which is how it was once squeezed to one line.
    @Test(arguments: [false, true], [CGSize(width: 402, height: 874), CGSize(width: 375, height: 667)])
    func theGiftDrawsTheWholeDoNotPurchaseWarning(charged: Bool, size: CGSize) async throws {
        let fixture = await fixture(
            startingAt: .exitGift,
            giftAlreadySeen: true,
            purchaseResult: charged ? .failed(RevenueCatPurchaseControllerError.entitlementUnconfirmed) : .pending
        )
        _ = await fixture.model.claimGift()

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: fixture.coordinator)
                .environment(\.onboardingPaywallModel, fixture.model)
                .environment(AuthenticationViewModel()),
            size: size,
            settle: .turns(40)
        ) { screen in
            _ = try await screen.copy(until: { $0.contains("check access") })
            try await Task.sleep(for: .seconds(2))
            let drawn = try await screen.recognizedText(scale: 2)
            #expect(drawn.contains("do not purchase again"), "\(drawn)")
            try screen.photograph(named: "onboarding-v3-gift-warning-\(charged ? "charged" : "ask-to-buy")-\(Int(size.height))")
        }
    }

    /// Dimmed cards are translucent, so the pinned area behind them has to be what stops the perks.
    @Test(arguments: [CGSize(width: 402, height: 874), CGSize(width: 375, height: 667)])
    func aLockedPaywallKeepsThePerksFromShowingThroughThePlanCards(size: CGSize) async throws {
        let fixture = await fixture(
            startingAt: .paywall,
            pending: PreAuthPendingPurchase(productID: "yearly", hold: .unconfirmedCharge)
        )

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: fixture.coordinator)
                .environment(\.onboardingPaywallModel, fixture.model)
                .environment(AuthenticationViewModel()),
            size: size,
            settle: .turns(40)
        ) { screen in
            _ = try await screen.copy(until: { $0.contains("check access") })
            try await Task.sleep(for: .seconds(1.2))

            let card = try #require(try await screen.frame(ofElementLabelled: "Yearly, best value"))
            var covered: PaywallPerk?
            for perk in PaywallPerk.all where covered == nil {
                if let row = try await screen.frame(ofElementLabelled: perk.title), row.intersects(card) {
                    covered = perk
                }
            }
            let perk = try #require(covered, "no perk scrolls behind the yearly card at this size")

            let drawn = try await screen.recognizedText(scale: 2)
            #expect(drawn.contains("$29.99"), "\(drawn)")
            #expect(drawn.contains("billed once a year"), "\(drawn)")
            #expect(!drawn.contains(perk.subtitle.lowercased()), "\(drawn)")
            try screen.photograph(named: "onboarding-v3-paywall-locked-\(Int(size.height))")
        }
    }

    /// Rendered glyphs, because the accessibility tree holds a word broken across two lines whole.
    /// The window is tall enough to draw the whole page at once; the width is what breaks a word.
    @Test(arguments: [CGFloat(375), 402], [DynamicTypeSize.accessibility3, .accessibility5])
    func noWordBreaksOnThePaywallAtAnAccessibilityTextSize(width: CGFloat, textSize: DynamicTypeSize) async throws {
        let fixture = await fixture(startingAt: .paywall)

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: fixture.coordinator)
                .environment(\.onboardingPaywallModel, fixture.model)
                .environment(AuthenticationViewModel())
                .environment(\.dynamicTypeSize, textSize),
            size: CGSize(width: width, height: 3200),
            settle: .turns(40)
        ) { screen in
            _ = try await screen.copy(until: { $0.contains("privacy") })
            try await Task.sleep(for: .seconds(1.2))

            let drawn = try await screen.recognizedText(scale: 2)
            for word in [
                "improving", "somewhere", "yearly", "best value", "$29.99", "lifetime", "renewal", "$49.99",
                "cancel", "anytime", "restore", "terms", "privacy"
            ] {
                #expect(drawn.contains(word), "\(word) did not draw whole: \(drawn)")
            }
            try screen.photograph(named: "onboarding-v3-paywall-words-\(Int(width))-\(textSize)")
        }
    }

    /// Rendered glyphs for the same reason as the paywall: 'WELCOM / E GIFT.' reads whole in the tree.
    @Test(arguments: [CGFloat(375), 402], [DynamicTypeSize.accessibility3, .accessibility5])
    func noWordBreaksOnTheClosedGiftAtAnAccessibilityTextSize(width: CGFloat, textSize: DynamicTypeSize) async throws {
        let fixture = await fixture(startingAt: .exitGift)

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: fixture.coordinator)
                .environment(\.onboardingPaywallModel, fixture.model)
                .environment(AuthenticationViewModel())
                .environment(\.dynamicTypeSize, textSize),
            size: CGSize(width: width, height: 2400),
            settle: .turns(40)
        ) { screen in
            _ = try await screen.copy(until: { $0.contains("tap to open") })
            try await Task.sleep(for: .seconds(1.2))

            let drawn = try await screen.recognizedText(scale: 2)
            for word in ["before", "open", "your", "welcome", "gift", "better", "price", "tap"] {
                #expect(drawn.contains(word), "\(word) did not draw whole: \(drawn)")
            }
            try screen.photograph(named: "onboarding-v3-gift-closed-words-\(Int(width))-\(textSize)")
        }
    }

    @Test(arguments: [CGFloat(375), 402], [DynamicTypeSize.accessibility3, .accessibility5])
    func noWordBreaksOnTheOpenGiftAtAnAccessibilityTextSize(width: CGFloat, textSize: DynamicTypeSize) async throws {
        let fixture = await fixture(startingAt: .exitGift, giftAlreadySeen: true)

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: fixture.coordinator)
                .environment(\.onboardingPaywallModel, fixture.model)
                .environment(AuthenticationViewModel())
                .environment(\.dynamicTypeSize, textSize),
            size: CGSize(width: width, height: 3200),
            settle: .turns(120)
        ) { screen in
            _ = try await screen.copy(until: { $0.contains("no thanks") })
            try await Task.sleep(for: .seconds(1.5))

            let drawn = try await screen.recognizedText(scale: 2)
            for word in ["welcome", "offer", "$9.99", "$29.99", "first", "week", "claim", "gift", "thanks"] {
                #expect(drawn.contains(word), "\(word) did not draw whole: \(drawn)")
            }
            try screen.photograph(named: "onboarding-v3-gift-open-words-\(Int(width))-\(textSize)")
        }
    }

    /// The stamp hangs over the voucher's top-right corner, and a label that just fits on one line ran
    /// under it. The tree still holds the whole label, so this reads pixels: the strip beside the stamp,
    /// on the rows the label starts on, carries no ink. The stamp's own shadow there is far from black.
    @Test(arguments: [CGFloat(375), 402], [DynamicTypeSize.xxxLarge, .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5])
    func theStampStaysClearOfTheWelcomeOfferLabel(width: CGFloat, textSize: DynamicTypeSize) async throws {
        let offer = try #require(await fixture(startingAt: .exitGift).model.giftOffer)

        try await RenderedScreen.host(
            ZStack(alignment: .top) {
                Color.black
                WelcomeGiftVoucher(offer: offer, copy: WelcomeGiftCopy(offer))
                    .padding(.horizontal, 26)
                    .padding(.top, 44)
            }
            .environment(\.dynamicTypeSize, textSize),
            size: CGSize(width: width, height: 874)
        ) { screen in
            _ = try #require(try await screen.frame(ofElementLabelled: "Welcome offer"))
            // From the layout above, because the element's frame also spans the stamp and the notches.
            let voucherTop = screen.root.safeAreaInsets.top + 44
            let voucherRight = width - 26
            let beside = CGRect(x: voucherRight - 78, y: voucherTop + 24, width: 12, height: 24)
            let voucher = CGRect(x: 26, y: voucherTop, width: voucherRight - 26, height: 0)

            let ink = try screen.withPixels(scale: 2) { pixels in
                pixels.count(in: beside) { $0.isNearBlack }
            }
            #expect(ink == 0, "the label reaches the stamp in \(beside) of \(voucher): \(ink) dark pixels")
            try screen.photograph(named: "onboarding-v3-voucher-\(Int(width))-\(textSize)")
        }
    }

    /// Scrolled to its end, the page has to stop below the close button rather than pass under it
    /// and on into the status bar.
    @Test(arguments: [CGSize(width: 402, height: 874), CGSize(width: 375, height: 667)])
    func scrollingThePerksKeepsTheHeadlineClearOfTheCloseButton(size: CGSize) async throws {
        let fixture = await fixture(startingAt: .paywall)

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: fixture.coordinator)
                .environment(\.onboardingPaywallModel, fixture.model)
                .environment(AuthenticationViewModel()),
            size: size,
            settle: .turns(40)
        ) { screen in
            _ = try await screen.copy(until: { $0.contains("close") })
            let close = try #require(try await screen.frame(ofElementLabelled: "Close"))

            let page = try #require(screen.root.descendants(of: UIScrollView.self).first { !$0.bounds.isEmpty })
            let end = page.contentSize.height + page.adjustedContentInset.bottom - page.bounds.height
            #expect(end > 0, "the page should scroll at this size")
            page.setContentOffset(CGPoint(x: 0, y: end), animated: false)
            try await screen.settle()
            try await Task.sleep(for: .seconds(1.2))

            let pageTop = page.convert(page.bounds, to: nil).minY
            #expect(pageTop >= close.maxY, "\(pageTop) starts above the close button's bottom, \(close.maxY)")
            if size == Self.smallestPhone {
                // Only here is the page long enough to carry the last line of the headline that far.
                let drawn = try await screen.recognizedText(scale: 2)
                #expect(!drawn.contains("again"), "\(drawn)")
            }
            try screen.photograph(named: "onboarding-v3-paywall-scrolled-\(Int(size.height))")
        }
    }

    /// At an accessibility size the plans scroll over the photograph, and dimmed cards are translucent.
    @Test
    func aLockedPlanCardScrolledOverThePhotographStaysReadable() async throws {
        let fixture = await fixture(
            startingAt: .paywall,
            pending: PreAuthPendingPurchase(productID: "yearly", hold: .unconfirmedCharge)
        )

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: fixture.coordinator)
                .environment(\.onboardingPaywallModel, fixture.model)
                .environment(AuthenticationViewModel())
                .environment(\.dynamicTypeSize, .accessibility3),
            size: Self.smallestPhone,
            settle: .turns(40)
        ) { screen in
            let page = try #require(screen.root.descendants(of: UIScrollView.self).first { !$0.bounds.isEmpty })
            // Beside the card, in the margin no text uses, and below where the page starts.
            let photoBand = CGRect(x: 0, y: 150, width: 18, height: 60)
            let brightest: @MainActor () throws -> Double = {
                try screen.withPixels { pixels in
                    pixels.pixels(in: photoBand).map(\.luminance).max() ?? 0
                }
            }
            _ = try await screen.copy(until: { $0.contains("never climb") })
            #expect(try brightest() > 30, "this band should hold the photograph before the card arrives")

            try await scrollLockedCard(to: photoBand.minY - 20, on: page, screen: screen)
            #expect(try brightest() < 30, "the photograph shows beside a locked card")
            let drawn = try await screen.recognizedText(scale: 2)
            #expect(drawn.contains("$29.99"), "\(drawn)")
            try screen.photograph(named: "onboarding-v3-paywall-locked-accessibility-scrolled")
        }
    }

    /// Scrolls the page until the yearly card's top sits at `wantedTop`.
    private func scrollLockedCard(to wantedTop: CGFloat, on page: UIScrollView, screen: HostedScreen) async throws {
        for _ in 0..<12 {
            guard let card = try await screen.text(containing: "Yearly, best value", reading: 20)?.frame else {
                page.setContentOffset(CGPoint(x: 0, y: page.contentOffset.y + 300), animated: false)
                try await screen.settle()
                continue
            }
            if abs(card.minY - wantedTop) < 2 { return }
            page.setContentOffset(CGPoint(x: 0, y: page.contentOffset.y + card.minY - wantedTop), animated: false)
            try await screen.settle()
        }
        Issue.record("the yearly card never reached the photograph")
    }

    @Test
    func withNoPlansTheMessageReadsCleanAndTheDeadButtonStaysStill() async throws {
        let fixture = await fixture(startingAt: .paywall, storeHasPlans: false)

        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: fixture.coordinator)
                .environment(\.onboardingPaywallModel, fixture.model)
                .environment(AuthenticationViewModel()),
            size: CGSize(width: 402, height: 874),
            settle: .turns(40)
        ) { screen in
            _ = try await screen.copy(until: { $0.contains("plans are unavailable") })
            try await Task.sleep(for: .seconds(1.2))

            let drawn = try await screen.recognizedText(scale: 2)
            #expect(drawn.contains("plans are unavailable right now"), "\(drawn)")
            #expect(drawn.contains("check your connection"), "\(drawn)")
            try screen.photograph(named: "onboarding-v3-paywall-no-plans")

            // Long enough for the 3.4 s sweep to cross the button at least once.
            let button = try #require(try await screen.frame(ofElementLabelled: "Start climbing"))
            var brightest = 0.0
            for _ in 0..<18 {
                let frameMax = try screen.withPixels { pixels in
                    pixels.pixels(in: button).map(\.luminance).max() ?? 0
                }
                brightest = max(brightest, frameMax)
                try await Task.sleep(for: .milliseconds(200))
            }
            #expect(brightest < 100, "a disabled button should not sweep a light: \(brightest)")
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
    let storeHasPlans: Bool

    init(trialEligible: Bool, purchaseResult: PurchaseResult, storeHasPlans: Bool) {
        self.trialEligible = trialEligible
        self.purchaseResult = purchaseResult
        self.storeHasPlans = storeHasPlans
    }

    func loadPlans() async throws -> [NativePaywallPlan] { try await loadPreAuthPlans() }

    func loadPreAuthPlans() async throws -> [NativePaywallPlan] {
        guard storeHasPlans else { return [] }
        return [
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
