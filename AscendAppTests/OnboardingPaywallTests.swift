import Foundation
import enum SuperwallKit.PurchaseResult
import Testing
@testable import AscendApp

// MARK: - The gift's numbers and words

@Suite
struct WelcomeGiftOfferTests {
    private func plan(
        _ id: String,
        price: Decimal,
        label: String,
        trial: NativeSubscriptionPeriod? = nil
    ) -> NativePaywallPlan {
        NativePaywallPlan(
            id: id,
            title: id,
            localizedPrice: label,
            billingDescription: "Renews annually",
            trialDescription: trial == nil ? nil : "free",
            price: price,
            freeTrialPeriod: trial
        )
    }

    @Test(arguments: [
        (Decimal(string: "29.99")!, Decimal(string: "9.99")!, 66),
        (Decimal(string: "29.99")!, Decimal(string: "14.99")!, 50),
        (Decimal(100), Decimal(0), 100)
    ])
    func thePercentComesFromTheTwoPricesAndRoundsDown(regular: Decimal, welcome: Decimal, expected: Int) {
        #expect(WelcomeGiftOffer.percentOff(regular: regular, welcome: welcome) == expected)
    }

    @Test
    func noDiscountIsNeverClaimed() {
        #expect(WelcomeGiftOffer.percentOff(regular: 9.99, welcome: 9.99) == nil)
        #expect(WelcomeGiftOffer.percentOff(regular: 9.99, welcome: 29.99) == nil)
        #expect(WelcomeGiftOffer.percentOff(regular: nil, welcome: 9.99) == nil)
        #expect(WelcomeGiftOffer.percentOff(regular: 29.99, welcome: nil) == nil)
        #expect(WelcomeGiftOffer.percentOff(regular: 0, welcome: 0) == nil)
    }

    @Test
    func anEligibleAppleIDGetsTheTrialLinesFromTheOfferItself() throws {
        let offer = try #require(WelcomeGiftOffer(
            welcome: plan("w", price: 9.99, label: "$9.99", trial: NativeSubscriptionPeriod(value: 1, unit: .week)),
            regular: plan("y", price: 29.99, label: "$29.99")
        ))
        let copy = WelcomeGiftCopy(offer)

        #expect(copy.trialLine == "PLUS 7 DAYS FREE")
        #expect(copy.headlineLead == ["Your first week"])
        #expect(copy.headlineAccent == ["is on us."])
        #expect(copy.subline == "Then $9.99 a year, locked in.")
        #expect(copy.finePrint == "Free today, then $9.99/year. Cancel anytime.")
        #expect(copy.stamp == "66%")
    }

    @Test
    func anAppleIDThatUsedItsTrialIsNeverPromisedOne() throws {
        let offer = try #require(WelcomeGiftOffer(
            welcome: plan("w", price: 9.99, label: "$9.99"),
            regular: plan("y", price: 29.99, label: "$29.99")
        ))
        let copy = WelcomeGiftCopy(offer)

        #expect(copy.trialLine == nil)
        #expect(copy.headlineLead == ["$9.99 a year,"])
        #expect(copy.headlineAccent == ["locked in."])
        #expect(copy.subline == "That's 66% off, every year you climb.")
        #expect(copy.finePrint == "$9.99 today, then every year. Cancel anytime.")
    }

    @Test
    func aTrialThatIsNotAWeekIsNamedByItsOwnLength() throws {
        let offer = try #require(WelcomeGiftOffer(
            welcome: plan("w", price: 9.99, label: "$9.99", trial: NativeSubscriptionPeriod(value: 1, unit: .month)),
            regular: plan("y", price: 29.99, label: "$29.99")
        ))
        let copy = WelcomeGiftCopy(offer)

        #expect(copy.trialLine == "PLUS 1 MONTH FREE")
        #expect(copy.headlineLead == ["Your first month"])
    }

    @Test(arguments: [
        (NativeSubscriptionPeriod(value: 1, unit: .day), "PLUS 1 DAY FREE", "Your first day", "is on us."),
        (NativeSubscriptionPeriod(value: 7, unit: .day), "PLUS 7 DAYS FREE", "Your first week", "is on us."),
        (NativeSubscriptionPeriod(value: 2, unit: .week), "PLUS 14 DAYS FREE", "Your first 14 days", "are on us."),
        (NativeSubscriptionPeriod(value: 2, unit: .month), "PLUS 2 MONTHS FREE", "Your first 2 months", "are on us."),
        (NativeSubscriptionPeriod(value: 1, unit: .year), "PLUS 1 YEAR FREE", "Your first year", "is on us.")
    ])
    func everyTrialLengthReadsAsASentence(
        period: NativeSubscriptionPeriod,
        trialLine: String,
        headline: String,
        accent: String
    ) throws {
        let offer = try #require(WelcomeGiftOffer(
            welcome: plan("w", price: 9.99, label: "$9.99", trial: period),
            regular: plan("y", price: 29.99, label: "$29.99")
        ))
        let copy = WelcomeGiftCopy(offer)

        #expect(copy.trialLine == trialLine)
        #expect(copy.headlineLead == [headline])
        #expect(copy.headlineAccent == [accent])
    }

    @Test
    func aStorePriceInAnotherCurrencyIsQuotedAsTheStoreWritesIt() throws {
        let offer = try #require(WelcomeGiftOffer(
            welcome: plan("w", price: 9.99, label: "9,99 €", trial: NativeSubscriptionPeriod(value: 7, unit: .day)),
            regular: plan("y", price: 29.99, label: "29,99 €")
        ))

        #expect(WelcomeGiftCopy(offer).finePrint == "Free today, then 9,99 €/year. Cancel anytime.")
    }

    @Test
    func aOneTimePurchaseIsNotAGift() {
        let lifetime = NativePaywallPlan(
            id: "l", title: "l", localizedPrice: "$49.99", billing: .oneTime,
            billingDescription: "", trialDescription: nil, price: 49.99
        )

        #expect(WelcomeGiftOffer(welcome: lifetime, regular: lifetime) == nil)
    }

    /// The copy rules for the whole flow, held against every string the gift can say.
    @Test
    func noGiftLineBreaksTheCopyRules() throws {
        let eligible = try #require(WelcomeGiftOffer(
            welcome: plan("w", price: 9.99, label: "$9.99", trial: NativeSubscriptionPeriod(value: 1, unit: .week)),
            regular: plan("y", price: 29.99, label: "$29.99")
        ))
        let ineligible = try #require(WelcomeGiftOffer(
            welcome: plan("w", price: 9.99, label: "$9.99"),
            regular: plan("y", price: 29.99, label: "$29.99")
        ))

        for offer in [eligible, ineligible] {
            let copy = WelcomeGiftCopy(offer)
            let words = (
                [copy.trialLine ?? ""] + copy.headlineLead + copy.headlineAccent
                    + [copy.subline, copy.callToAction, copy.finePrint]
                    + OnboardingPaywallModel.Notice.allMessages
            ).joined(separator: " ").lowercased()

            #expect(!words.contains("\u{2014}"))
            #expect(!words.contains("race"))
            #expect(!words.contains("live"))
            #expect(!words.contains("field"))
            #expect(!words.contains("show up again"))
            #expect(!words.contains("one-time"))
            #expect(!words.contains("ends in"))
        }
    }
}

extension OnboardingPaywallModel.Notice {
    static var allMessages: [String] {
        let all: [OnboardingPaywallModel.Notice] = [.plansUnavailable, .checkoutFailed, .pendingApproval, .verificationUnavailable,
         .nothingToRestore, .restoreFailed, .accountUnavailable]
        return all.map(\.message)
    }
}

// MARK: - The hold store

@Suite
struct PendingPurchaseHoldStoreTests {
    private func store() -> PendingPurchaseHoldStore {
        PendingPurchaseHoldStore(userDefaults: UserDefaults(suiteName: "PendingPurchaseHoldStoreTests-\(UUID().uuidString)")!)
    }

    @Test
    func aFreshInstallHoldsNothing() {
        #expect(store().hold() == nil)
    }

    @Test
    func aHoldIsKeptUntilItIsCleared() {
        let store = store()
        let hold = PendingPurchaseHold.askToBuy
        store.mark(hold)
        #expect(store.hold() == hold)

        store.clear()
        #expect(store.hold() == nil)
    }

    @Test
    func aValueNothingCanDecodeReadsAsNoHold() {
        let suite = "PendingPurchaseHoldStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("not a hold", forKey: PendingPurchaseHoldStore.storageKey)

        #expect(PendingPurchaseHoldStore(userDefaults: defaults).hold() == nil)
    }
}

// MARK: - The model

@MainActor
private final class StubPlanProvider: OnboardingPaywallPlanProviding {
    var plans: [NativePaywallPlan]
    var loadError: (any Error)?
    var purchaseResult: PurchaseResult = .purchased
    private(set) var purchasedPlanIDs: [String] = []

    init(plans: [NativePaywallPlan]) { self.plans = plans }

    func loadPlans() async throws -> [NativePaywallPlan] { plans }

    func loadOnboardingPlans() async throws -> [NativePaywallPlan] {
        if let loadError { throw loadError }
        return plans
    }

    func purchase(planID: String) async -> PurchaseResult {
        purchasedPlanIDs.append(planID)
        return purchaseResult
    }
}

@MainActor
@Suite
struct OnboardingPaywallModelTests {
    private static let configuration = MonetizationConfiguration(infoDictionary: [
        MonetizationConfiguration.revenueCatYearlyProductIDInfoKey: "yearly",
        MonetizationConfiguration.revenueCatLifetimeProductIDInfoKey: "lifetime",
        MonetizationConfiguration.revenueCatWelcomeProductIDInfoKey: "welcome"
    ])

    private func plans(trial: Bool = true) -> [NativePaywallPlan] {
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
                billingDescription: "Renews annually", trialDescription: trial ? "7 days free" : nil,
                price: 9.99, freeTrialPeriod: trial ? NativeSubscriptionPeriod(value: 1, unit: .week) : nil
            )
        ]
    }

    private func make(
        provider: StubPlanProvider,
        entitlement: MonetizationEntitlementState = .inactive,
        entitlementService: EntitlementServiceStub? = nil,
        holdStore: PendingPurchaseHoldStore? = nil
    ) -> (OnboardingPaywallModel, PendingPurchaseHoldStore) {
        let holdStore = holdStore ?? PendingPurchaseHoldStore(
            userDefaults: UserDefaults(suiteName: "OnboardingPaywallModelTests-\(UUID().uuidString)")!
        )
        let manager = MonetizationManager(
            configuration: Self.configuration,
            entitlementService: entitlementService ?? EntitlementServiceStub(entitlementState: entitlement),
            paywallPresenter: NoopPresenter(),
            appAccessReconciler: NoopReconciler(),
            userDefaults: UserDefaults(suiteName: "OnboardingPaywallModelTests-m-\(UUID().uuidString)")!
        )
        let model = OnboardingPaywallModel(
            provider: provider,
            monetization: manager,
            restoreService: AppAccessRestoreService(
                entitlementID: "app_access",
                restorer: { manager }
            ),
            holdStore: holdStore
        )
        return (model, holdStore)
    }

    @Test
    func loadingFillsTheThreePlansAndSelectsYearly() async {
        let (model, _) = make(provider: StubPlanProvider(plans: plans()))
        await model.load()

        #expect(model.loadState == .ready)
        #expect(model.yearly?.id == "yearly")
        #expect(model.lifetime?.id == "lifetime")
        #expect(model.welcome?.id == "welcome")
        #expect(model.selectedPlan?.id == "yearly")
        #expect(model.giftOffer?.percentOff == 66)
    }

    @Test
    func aStoreWithNoYearlyPlanIsUnavailableAndHasNoGift() async {
        let provider = StubPlanProvider(plans: [])
        let (model, _) = make(provider: provider)
        await model.load()

        #expect(model.loadState == .unavailable)
        #expect(model.notice == .plansUnavailable)
        #expect(model.giftOffer == nil)
    }

    @Test
    func aProductAppleHasNotApprovedLeavesNoGiftBehindTheCloseButton() async {
        let (model, _) = make(provider: StubPlanProvider(plans: Array(plans().prefix(2))))
        await model.load()

        #expect(model.loadState == .ready)
        #expect(model.giftOffer == nil)
    }

    @Test
    func aPurchaseBuysTheSelectedPlanForTheSignedInAccount() async {
        let provider = StubPlanProvider(plans: plans())
        let (model, store) = make(provider: provider)
        await model.load()

        let outcome = await model.purchaseSelectedPlan()

        #expect(outcome == .purchased)
        #expect(provider.purchasedPlanIDs == ["yearly"])
        #expect(model.holdsAccess)
        #expect(store.hold() == nil)
    }

    @Test
    func claimingTheGiftBuysTheWelcomeProductAndReportsTheTrial() async {
        let provider = StubPlanProvider(plans: plans())
        let (model, _) = make(provider: provider)
        await model.load()

        let outcome = await model.claimGift()

        #expect(outcome == .purchased)
        #expect(provider.purchasedPlanIDs == ["welcome"])
    }

    @Test
    func lifetimeIsBoughtAsItsOwnPlan() async {
        let provider = StubPlanProvider(plans: plans())
        let (model, _) = make(provider: provider)
        await model.load()
        model.selectedPlanID = "lifetime"

        _ = await model.purchaseSelectedPlan()

        #expect(provider.purchasedPlanIDs == ["lifetime"])
    }

    @Test
    func aCancelledPurchaseLeavesNothingBehind() async {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = .cancelled
        let (model, store) = make(provider: provider)
        await model.load()

        #expect(await model.purchaseSelectedPlan() == .cancelled)
        #expect(store.hold() == nil)
        #expect(model.notice == nil)
        #expect(model.activity == .idle)
    }

    @Test
    func aPendingPurchaseTellsTheClimberNotToBuyAgain() async {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = .pending
        let (model, store) = make(provider: provider)
        await model.load()

        #expect(await model.purchaseSelectedPlan() == .notCompleted)
        #expect(model.notice == .pendingApproval)
        #expect(store.hold() == PendingPurchaseHold.askToBuy)
    }

    @Test
    func aFailedPurchaseIsReportedAndRetryable() async {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = .failed(RevenueCatPurchaseControllerError.missingStoreKitProduct)
        let (model, _) = make(provider: provider)
        await model.load()

        #expect(await model.purchaseSelectedPlan() == .notCompleted)
        #expect(model.notice == .checkoutFailed)
        #expect(model.activity == .idle)
    }

    @Test
    func anAccountThatAlreadyHoldsAccessSaysSo() async {
        let (model, _) = make(
            provider: StubPlanProvider(plans: plans()),
            entitlement: .active(["app_access"])
        )
        await model.load()

        #expect(model.holdsAccess)
    }

    private func unconfirmedPurchaseResult(isAskToBuy: Bool) -> PurchaseResult {
        isAskToBuy ? .pending : .failed(RevenueCatPurchaseControllerError.entitlementUnconfirmed)
    }

    @Test(arguments: [true, false])
    func nothingElseCanBeBoughtWhileAPurchaseIsUnconfirmed(isAskToBuy: Bool) async {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = unconfirmedPurchaseResult(isAskToBuy: isAskToBuy)
        let (model, _) = make(provider: provider)
        await model.load()
        _ = await model.purchaseSelectedPlan()
        provider.purchaseResult = .purchased

        model.selectedPlanID = "lifetime"
        #expect(await model.purchaseSelectedPlan() == .notCompleted)
        #expect(await model.claimGift() == .notCompleted)

        #expect(provider.purchasedPlanIDs == ["yearly"])
        #expect(model.locksPurchase)
    }

    @Test(arguments: [true, false])
    func theWarningSurvivesThePaywallLoadingAgain(isAskToBuy: Bool) async {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = unconfirmedPurchaseResult(isAskToBuy: isAskToBuy)
        let (model, _) = make(provider: provider)
        await model.load()
        _ = await model.claimGift()

        await model.load()

        #expect(model.notice == (isAskToBuy ? .pendingApproval : .verificationUnavailable))
        #expect(model.isAwaitingConfirmation)
    }

    @Test
    func checkingWithNoAccessYetKeepsTheLockAndTheWarning() async {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = .pending
        let (model, _) = make(provider: provider)
        await model.load()
        _ = await model.purchaseSelectedPlan()

        await model.checkAccess()

        #expect(model.notice == .pendingApproval)
        #expect(model.isAwaitingConfirmation)
        #expect(model.activity == .idle)
    }

    @Test
    func accessThatLandsAfterAnUnconfirmedPurchaseIsSeenAndTheRootReleasesTheHold() async {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = .pending
        let service = EntitlementServiceStub(entitlementState: .inactive)
        let (model, store) = make(provider: provider, entitlementService: service)
        await model.load()
        _ = await model.claimGift()

        service.setEntitlementState(.active(["app_access"]))
        await model.checkAccess()
        #expect(model.holdsAccess)

        model.releaseUnconfirmedPurchase()
        #expect(!model.isAwaitingConfirmation)
        #expect(store.hold() == nil)
    }

    @Test
    func aRestoreThatFindsNothingEndsADeclinedAskToBuy() async {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = .pending
        let service = EntitlementServiceStub(entitlementState: .inactive)
        let (model, store) = make(provider: provider, entitlementService: service)
        await model.load()
        _ = await model.purchaseSelectedPlan()

        #expect(await model.restore() == .notCompleted)

        #expect(model.notice == .nothingToRestore)
        #expect(!model.locksPurchase)
        #expect(store.hold() == nil)
        provider.purchaseResult = .purchased
        #expect(await model.purchaseSelectedPlan() == .purchased)
    }

    @Test
    func aRestoreThatFindsNothingKeepsTheLockOnAnUnconfirmedCharge() async {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = .failed(RevenueCatPurchaseControllerError.entitlementUnconfirmed)
        let (model, store) = make(provider: provider)
        await model.load()
        _ = await model.purchaseSelectedPlan()

        #expect(await model.restore() == .notCompleted)

        #expect(model.notice == .verificationUnavailable)
        #expect(model.locksPurchase)
        #expect(store.hold() == .unconfirmedCharge)
        model.selectedPlanID = "lifetime"
        #expect(await model.purchaseSelectedPlan() == .notCompleted)
        #expect(provider.purchasedPlanIDs == ["yearly"])
    }

    @Test
    func aRestoreThatFindsTheUnconfirmedChargeReleasesTheHold() async {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = .failed(RevenueCatPurchaseControllerError.entitlementUnconfirmed)
        let service = EntitlementServiceStub(entitlementState: .inactive)
        service.restoredState = .active(["app_access"])
        let (model, store) = make(provider: provider, entitlementService: service)
        await model.load()
        _ = await model.claimGift()

        #expect(await model.restore() == .restored)

        #expect(!model.isAwaitingConfirmation)
        #expect(store.hold() == nil)
    }

    private func relaunched(
        after result: PurchaseResult,
        provider relaunchedProvider: StubPlanProvider
    ) async -> (OnboardingPaywallModel, PendingPurchaseHoldStore) {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = result
        let (first, store) = make(provider: provider)
        await first.load()
        _ = await first.claimGift()

        let (model, _) = make(provider: relaunchedProvider, holdStore: store)
        await model.load()
        return (model, store)
    }

    @Test
    func aRelaunchedUnconfirmedChargeStaysLockedThroughARestoreThatFindsNothing() async {
        let provider = StubPlanProvider(plans: plans())
        let (model, store) = await relaunched(
            after: .failed(RevenueCatPurchaseControllerError.entitlementUnconfirmed),
            provider: provider
        )

        #expect(store.hold() == PendingPurchaseHold.unconfirmedCharge)
        #expect(model.notice == .verificationUnavailable)
        #expect(await model.purchaseSelectedPlan() == .notCompleted)
        #expect(await model.claimGift() == .notCompleted)
        #expect(provider.purchasedPlanIDs.isEmpty)

        #expect(await model.restore() == .notCompleted)

        #expect(model.locksPurchase)
        #expect(model.notice == .verificationUnavailable)
    }

    @Test
    func aRelaunchedAskToBuyIsLockedUntilARestoreFindsItDeclined() async {
        let provider = StubPlanProvider(plans: plans())
        let (model, store) = await relaunched(after: .pending, provider: provider)

        #expect(store.hold() == PendingPurchaseHold.askToBuy)
        #expect(model.notice == .pendingApproval)
        #expect(await model.purchaseSelectedPlan() == .notCompleted)
        #expect(provider.purchasedPlanIDs.isEmpty)

        #expect(await model.restore() == .notCompleted)

        #expect(model.notice == .nothingToRestore)
        #expect(!model.locksPurchase)
        #expect(store.hold() == nil)
        #expect(await model.purchaseSelectedPlan() == .purchased)
    }

    @Test
    func nothingCanBeBoughtOnceAPurchaseHasCompleted() async {
        let provider = StubPlanProvider(plans: plans())
        let (model, _) = make(provider: provider)
        await model.load()
        _ = await model.purchaseSelectedPlan()

        model.selectedPlanID = "lifetime"
        #expect(model.locksPurchase)
        #expect(await model.purchaseSelectedPlan() == .notCompleted)
        #expect(await model.claimGift() == .notCompleted)

        #expect(provider.purchasedPlanIDs == ["yearly"])
    }

    @Test
    func nothingCanBeBoughtByAnAccountThatAlreadyHoldsAccess() async {
        let provider = StubPlanProvider(plans: plans())
        let (model, _) = make(provider: provider, entitlement: .active(["app_access"]))
        await model.load()

        #expect(await model.purchaseSelectedPlan() == .notCompleted)
        #expect(provider.purchasedPlanIDs.isEmpty)
    }

    @Test
    func aRelaunchedLockHoldsEvenWhenThePlansCannotLoad() async {
        let provider = StubPlanProvider(plans: [])
        let store = PendingPurchaseHoldStore(
            userDefaults: UserDefaults(suiteName: "OnboardingPaywallModelTests-\(UUID().uuidString)")!
        )
        store.mark(PendingPurchaseHold.unconfirmedCharge)
        let (model, _) = make(provider: provider, holdStore: store)
        await model.load()

        #expect(model.loadState == .unavailable)
        #expect(model.isAwaitingConfirmation)
    }

    @Test
    func releasingTheHoldOnSignOutDoesNotLockTheNextAccount() async {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = .pending
        let (first, store) = make(provider: provider)
        await first.load()
        _ = await first.purchaseSelectedPlan()
        #expect(first.isAwaitingConfirmation)

        first.releaseUnconfirmedPurchase()
        let (next, _) = make(provider: StubPlanProvider(plans: plans()), holdStore: store)

        #expect(store.hold() == nil)
        #expect(!next.isAwaitingConfirmation)
    }

    @Test
    func aReleasedAskToBuyDoesNotComeBackOnRelaunch() async {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = .pending
        let (first, store) = make(provider: provider)
        await first.load()
        _ = await first.purchaseSelectedPlan()
        _ = await first.restore()

        let (relaunched, _) = make(provider: StubPlanProvider(plans: plans()), holdStore: store)

        #expect(store.hold() == nil)
        #expect(!relaunched.isAwaitingConfirmation)
    }

    @Test
    func aCancelledOrFailedPurchaseLeavesNoMarker() async {
        let provider = StubPlanProvider(plans: plans())
        let (model, store) = make(provider: provider)
        await model.load()

        provider.purchaseResult = .cancelled
        _ = await model.purchaseSelectedPlan()
        #expect(store.hold() == nil)

        provider.purchaseResult = .failed(RevenueCatPurchaseControllerError.missingStoreKitProduct)
        _ = await model.purchaseSelectedPlan()
        #expect(store.hold() == nil)
        #expect(!model.locksPurchase)
    }

    @Test
    func resettingDropsAOneOffNoticeButKeepsTheWarning() async {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = .failed(RevenueCatPurchaseControllerError.missingStoreKitProduct)
        let (model, _) = make(provider: provider)
        await model.load()
        _ = await model.purchaseSelectedPlan()
        #expect(model.notice == .checkoutFailed)
        model.resetNotice()
        #expect(model.notice == nil)

        provider.purchaseResult = .pending
        _ = await model.purchaseSelectedPlan()
        model.resetNotice()
        #expect(model.notice == .pendingApproval)
    }
}

@MainActor
private final class NoopPresenter: PaywallPresenting {
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
private final class NoopReconciler: AppAccessReconciling {
    func reconcileAppAccess(force: Bool) async {}
}

// MARK: - The welcome product and the purchase identity

struct WelcomeProductConfigurationTests {
    @Test
    func theWelcomeProductIsReadFromTheBuildAndSoldOnlyByTheGift() {
        let configuration = MonetizationConfiguration(infoDictionary: [
            MonetizationConfiguration.revenueCatYearlyProductIDInfoKey: "ascend_yearly",
            MonetizationConfiguration.revenueCatLifetimeProductIDInfoKey: "ascend_lifetime",
            MonetizationConfiguration.revenueCatWelcomeProductIDInfoKey: "ascend_yearly_welcome"
        ])

        #expect(configuration.revenueCatWelcomeProductID == "ascend_yearly_welcome")
        #expect(configuration.launchProductIDs == ["ascend_yearly", "ascend_lifetime"])
        #expect(configuration.onboardingProductIDs == ["ascend_yearly", "ascend_lifetime", "ascend_yearly_welcome"])
    }

    @Test
    func aMissingSubstitutionNeverBecomesARealProductID() {
        let configuration = MonetizationConfiguration(infoDictionary: [
            MonetizationConfiguration.revenueCatWelcomeProductIDInfoKey: "$(ASCEND_REVENUECAT_WELCOME_PRODUCT_ID)"
        ])

        #expect(configuration.revenueCatWelcomeProductID.hasPrefix("UNCONFIGURED_"))
    }

    @Test
    func theMapperAddsTheWelcomePlanOnlyWhenAsked() {
        let products = [
            NativePaywallProductTerms(
                productID: "y", localizedPrice: "$29.99",
                renewalPeriod: NativeSubscriptionPeriod(value: 1, unit: .year), freeTrialPeriod: nil
            ),
            NativePaywallProductTerms(
                productID: "w", localizedPrice: "$9.99",
                renewalPeriod: NativeSubscriptionPeriod(value: 1, unit: .year),
                freeTrialPeriod: NativeSubscriptionPeriod(value: 1, unit: .week),
                price: 9.99
            )
        ]

        let launch = NativePaywallPlanMapper.plans(
            from: products, eligibilityByProductID: [:], yearlyProductID: "y", lifetimeProductID: "l"
        )
        #expect(launch.map(\.id) == ["y"])

        let onboarding = NativePaywallPlanMapper.plans(
            from: products, eligibilityByProductID: ["w": .eligible],
            yearlyProductID: "y", lifetimeProductID: "l", welcomeProductID: "w",
            locale: Locale(identifier: "en_US")
        )
        #expect(onboarding.map(\.id) == ["y", "w"])
        #expect(onboarding.last?.title == "Annual")
        #expect(onboarding.last?.freeTrialPeriod == NativeSubscriptionPeriod(value: 1, unit: .week))
        #expect(onboarding.last?.price == 9.99)

        let used = NativePaywallPlanMapper.plans(
            from: products, eligibilityByProductID: ["w": .ineligible],
            yearlyProductID: "y", lifetimeProductID: "l", welcomeProductID: "w"
        )
        #expect(used.last?.freeTrialPeriod == nil)
        #expect(used.last?.trialDescription == nil)
    }
}

@MainActor
@Suite
struct PurchaseIdentityTests {
    private func executor(identity: MonetizationIdentityTransition?) -> RevenueCatPurchaseExecutor {
        RevenueCatPurchaseExecutor(
            transactionContextStore: PaywallTransactionContextStore(),
            entitlementID: "app_access",
            applySubscriptionStatus: { _ in },
            refreshEntitlementState: { .refreshed(.unknown) },
            currentIdentityGeneration: { identity },
            adoptEntitlementState: { _, _ in true }
        )
    }

    @Test
    func aSignedInAccountBuys() async {
        let account = MonetizationIdentityTransition(revision: 3, userID: "u1")
        let result = await executor(identity: account).executePurchase(productID: "y") {
            .init(userCancelled: false, entitlementState: .active(["app_access"]))
        }

        guard case .purchased = result else { Issue.record("expected a purchase, got \(result)"); return }
    }

    @Test
    func aPurchaseWithNoUidIsRefusedBeforeAnythingIsCharged() async {
        var ran = false
        let anonymous = MonetizationIdentityTransition(revision: 3, userID: nil)
        let result = await executor(identity: anonymous).executePurchase(productID: "y") {
            ran = true
            return .init(userCancelled: false, entitlementState: .active(["app_access"]))
        }

        #expect(!ran)
        guard case .failed = result else { Issue.record("expected a refusal"); return }
    }

    @Test
    func noIdentityAtAllIsRefusedToo() async {
        var ran = false
        let result = await executor(identity: nil).executePurchase(productID: "y") {
            ran = true
            return .init(userCancelled: false, entitlementState: .active(["app_access"]))
        }

        #expect(!ran)
        guard case .failed = result else { Issue.record("expected a refusal"); return }
    }
}
