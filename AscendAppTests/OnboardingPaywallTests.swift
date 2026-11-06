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

// MARK: - The ledger and the route

@Suite
struct PreAuthPurchaseLedgerTests {
    private func ledger() -> PreAuthPurchaseLedger {
        PreAuthPurchaseLedger(userDefaults: UserDefaults(suiteName: "PreAuthPurchaseLedgerTests-\(UUID().uuidString)")!)
    }

    @Test
    func aFreshInstallStartsAtTheBeginning() {
        #expect(ledger().resumeStep == nil)
    }

    @Test
    func reachingThePaywallResumesThereAndABoughtPlanResumesAtSignIn() {
        let ledger = ledger()
        ledger.markPaywallReached()
        #expect(ledger.resumeStep == .paywall)

        ledger.recordPurchase(PreAuthPurchase(productID: "y", purchasedAt: Date(), startedTrial: true))
        #expect(ledger.resumeStep == .auth)
        #expect(ledger.progress().purchase?.startedTrial == true)
    }

    @Test
    func theFirstTimeAtThePaywallIsKept() {
        let ledger = ledger()
        let first = Date(timeIntervalSince1970: 100)
        ledger.markPaywallReached(at: first)
        ledger.markPaywallReached(at: Date(timeIntervalSince1970: 900))

        #expect(ledger.progress().reachedPaywallAt == first)
    }

    @Test
    func clearingForgetsEverything() {
        let ledger = ledger()
        ledger.markPaywallReached()
        ledger.recordPurchase(PreAuthPurchase(productID: "y", purchasedAt: Date(), startedTrial: false))
        ledger.clear()

        #expect(ledger.resumeStep == nil)
        #expect(ledger.progress() == PreAuthPaywallProgress())
    }
}

// MARK: - The model

@MainActor
private final class StubPlanProvider: PreAuthPaywallPlanProviding {
    var plans: [NativePaywallPlan]
    var loadError: (any Error)?
    var purchaseResult: PurchaseResult = .purchased
    private(set) var purchasedPlanIDs: [String] = []

    init(plans: [NativePaywallPlan]) { self.plans = plans }

    func loadPlans() async throws -> [NativePaywallPlan] { plans }

    func loadPreAuthPlans() async throws -> [NativePaywallPlan] {
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
        ledger: PreAuthPurchaseLedger? = nil
    ) -> (OnboardingPaywallModel, PreAuthPurchaseLedger) {
        let ledger = ledger ?? PreAuthPurchaseLedger(
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
            ledger: ledger
        )
        return (model, ledger)
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
    func aPurchaseIsRememberedUntilSignInMovesIt() async {
        let provider = StubPlanProvider(plans: plans())
        let (model, ledger) = make(provider: provider)
        await model.load()

        let outcome = await model.purchaseSelectedPlan()

        #expect(outcome == .purchased(startedTrial: false))
        #expect(provider.purchasedPlanIDs == ["yearly"])
        #expect(ledger.resumeStep == .auth)
        #expect(ledger.progress().purchase?.productID == "yearly")
    }

    @Test
    func claimingTheGiftBuysTheWelcomeProductAndRecordsTheTrial() async {
        let provider = StubPlanProvider(plans: plans())
        let (model, ledger) = make(provider: provider)
        await model.load()

        let outcome = await model.claimGift()

        #expect(outcome == .purchased(startedTrial: true))
        #expect(provider.purchasedPlanIDs == ["welcome"])
        #expect(ledger.progress().purchase?.startedTrial == true)
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
        let (model, ledger) = make(provider: provider)
        await model.load()

        #expect(await model.purchaseSelectedPlan() == .cancelled)
        #expect(ledger.resumeStep == nil)
        #expect(model.notice == nil)
        #expect(model.activity == .idle)
    }

    @Test
    func aPendingPurchaseTellsTheClimberNotToBuyAgain() async {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = .pending
        let (model, ledger) = make(provider: provider)
        await model.load()

        #expect(await model.purchaseSelectedPlan() == .notCompleted)
        #expect(model.notice == .pendingApproval)
        #expect(ledger.resumeStep == nil)
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
    func anInstallThatAlreadyHoldsAccessSaysSo() async {
        let (model, _) = make(
            provider: StubPlanProvider(plans: plans()),
            entitlement: .active(["app_access"])
        )
        await model.load()

        #expect(model.holdsAccess)
    }

    @Test(arguments: [true, false])
    func accessThatArrivesAfterThePurchaseCallIsRememberedAsThatPurchase(isAskToBuy: Bool) async throws {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = isAskToBuy
            ? .pending
            : .failed(RevenueCatPurchaseControllerError.entitlementUnconfirmed)
        let service = EntitlementServiceStub(entitlementState: .inactive)
        let (model, ledger) = make(provider: provider, entitlementService: service)
        await model.load()

        #expect(await model.claimGift() == .notCompleted)
        #expect(ledger.resumeStep == nil)

        service.setEntitlementState(.active(["app_access"]))
        let startedTrial = model.recordHeldAccess()

        #expect(startedTrial)
        #expect(ledger.resumeStep == .auth)
        let purchase = try #require(ledger.progress().purchase)
        #expect(purchase.source == .purchase)
        #expect(purchase.productID == "welcome")
        #expect(purchase.startedTrial)
    }

    @Test
    func accessWithNoPurchaseBehindItIsRememberedAsRestored() async {
        let (model, ledger) = make(
            provider: StubPlanProvider(plans: plans()),
            entitlement: .active(["app_access"])
        )
        await model.load()

        #expect(!model.recordHeldAccess())
        #expect(ledger.resumeStep == .auth)
        #expect(ledger.progress().purchase?.source == .restore)
    }

    @Test
    func recordingHeldAccessKeepsThePurchaseAlreadyRecorded() async throws {
        let provider = StubPlanProvider(plans: plans())
        let service = EntitlementServiceStub(entitlementState: .inactive)
        let (model, ledger) = make(provider: provider, entitlementService: service)
        await model.load()
        _ = await model.claimGift()
        let recorded = try #require(ledger.progress().purchase)

        service.setEntitlementState(.active(["app_access"]))

        #expect(model.recordHeldAccess())
        #expect(ledger.progress().purchase == recorded)
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
    func checkingAfterAccessLandsReleasesTheLockOnceTheHoldingIsRecorded() async {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = .pending
        let service = EntitlementServiceStub(entitlementState: .inactive)
        let (model, ledger) = make(provider: provider, entitlementService: service)
        await model.load()
        _ = await model.claimGift()

        service.setEntitlementState(.active(["app_access"]))
        await model.checkAccess()
        #expect(model.holdsAccess)

        #expect(model.recordHeldAccess())
        #expect(ledger.progress().purchase?.productID == "welcome")
        #expect(!model.isAwaitingConfirmation)
        #expect(model.notice == nil)
    }

    @Test
    func aRestoreThatFindsNothingEndsADeclinedAskToBuy() async {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = .pending
        let service = EntitlementServiceStub(entitlementState: .inactive)
        let (model, ledger) = make(provider: provider, entitlementService: service)
        await model.load()
        _ = await model.purchaseSelectedPlan()

        #expect(await model.restore() == .notCompleted)

        #expect(model.notice == .nothingToRestore)
        #expect(!model.locksPurchase)
        #expect(ledger.resumeStep == nil)
        provider.purchaseResult = .purchased
        #expect(await model.purchaseSelectedPlan() == .purchased(startedTrial: false))
    }

    @Test
    func aRestoreThatFindsNothingKeepsTheLockOnAnUnconfirmedCharge() async {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = .failed(RevenueCatPurchaseControllerError.entitlementUnconfirmed)
        let (model, ledger) = make(provider: provider)
        await model.load()
        _ = await model.purchaseSelectedPlan()

        #expect(await model.restore() == .notCompleted)

        #expect(model.notice == .verificationUnavailable)
        #expect(model.locksPurchase)
        #expect(ledger.progress().pendingPurchase?.productID == "yearly")
        model.selectedPlanID = "lifetime"
        #expect(await model.purchaseSelectedPlan() == .notCompleted)
        #expect(provider.purchasedPlanIDs == ["yearly"])
    }

    private func relaunched(
        after result: PurchaseResult,
        provider relaunchedProvider: StubPlanProvider
    ) async -> (OnboardingPaywallModel, PreAuthPurchaseLedger) {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = result
        let (first, ledger) = make(provider: provider)
        await first.load()
        _ = await first.claimGift()
        ledger.markPaywallReached()

        let (model, _) = make(provider: relaunchedProvider, ledger: ledger)
        await model.load()
        return (model, ledger)
    }

    @Test
    func aRelaunchedUnconfirmedChargeStaysLockedThroughARestoreThatFindsNothing() async {
        let provider = StubPlanProvider(plans: plans())
        let (model, ledger) = await relaunched(
            after: .failed(RevenueCatPurchaseControllerError.entitlementUnconfirmed),
            provider: provider
        )

        #expect(ledger.resumeStep == .paywall)
        #expect(ledger.progress().pendingPurchase == PreAuthPendingPurchase(productID: "welcome", hold: .unconfirmedCharge))
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
        let (model, ledger) = await relaunched(after: .pending, provider: provider)

        #expect(ledger.progress().pendingPurchase == PreAuthPendingPurchase(productID: "welcome", hold: .askToBuy))
        #expect(model.notice == .pendingApproval)
        #expect(await model.purchaseSelectedPlan() == .notCompleted)
        #expect(provider.purchasedPlanIDs.isEmpty)

        #expect(await model.restore() == .notCompleted)

        #expect(model.notice == .nothingToRestore)
        #expect(!model.locksPurchase)
        #expect(ledger.progress().pendingPurchase == nil)
        #expect(await model.purchaseSelectedPlan() == .purchased(startedTrial: false))
    }

    @Test
    func aTrialStartedThisSessionSurvivesThePlansReloadingWithoutIt() async {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = .failed(RevenueCatPurchaseControllerError.entitlementUnconfirmed)
        let service = EntitlementServiceStub(entitlementState: .inactive)
        let (model, ledger) = make(provider: provider, entitlementService: service)
        await model.load()
        _ = await model.claimGift()

        provider.plans = plans(trial: false)
        await model.load()
        service.setEntitlementState(.active(["app_access"]))

        #expect(model.recordHeldAccess())
        #expect(ledger.progress().purchase?.startedTrial == true)
    }

    @Test
    func theSignInExitReleasesAnAskToBuyButNotACharge() async {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = .pending
        let (askToBuy, askToBuyLedger) = make(provider: provider)
        await askToBuy.load()
        _ = await askToBuy.purchaseSelectedPlan()

        askToBuy.releaseAskToBuyHold()

        #expect(askToBuyLedger.progress().pendingPurchase == nil)
        #expect(!askToBuy.isAwaitingConfirmation)

        provider.purchaseResult = .failed(RevenueCatPurchaseControllerError.entitlementUnconfirmed)
        let (charge, chargeLedger) = make(provider: provider)
        await charge.load()
        _ = await charge.purchaseSelectedPlan()

        charge.releaseAskToBuyHold()

        #expect(chargeLedger.progress().pendingPurchase?.hold == .unconfirmedCharge)
        #expect(charge.locksPurchase)
    }

    private func signIn(
        after result: PurchaseResult,
        transferring: StubTransferring
    ) async -> (PreAuthPurchaseTransfer.Outcome, OnboardingPaywallModel, PreAuthPurchaseLedger) {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = result
        let (model, ledger) = make(provider: provider)
        await model.load()
        _ = await model.purchaseSelectedPlan()
        let transfer = PreAuthPurchaseTransfer(
            ledger: ledger,
            monetization: transferring,
            invoker: StubInvoker([.active]),
            releaseUnconfirmedPurchase: { model.releaseUnconfirmedPurchase() }
        )
        return (await transfer.completeAfterSignIn(), model, ledger)
    }

    @Test
    func aCompletedSignInMovesAnUnconfirmedChargeOntoAnAccountRevenueCatAlreadyKnew() async {
        let transferring = StubTransferring()
        transferring.restoredActive = true

        let (outcome, model, ledger) = await signIn(
            after: .failed(RevenueCatPurchaseControllerError.entitlementUnconfirmed),
            transferring: transferring
        )

        #expect(outcome == .granted)
        #expect(transferring.calls == ["refresh", "restore"])
        #expect(ledger.progress().pendingPurchase == nil)
        #expect(!model.isAwaitingConfirmation)
    }

    @Test
    func aChargeThatNeverReachesTheAccountIsReportedAndStillReleased() async {
        let transferring = StubTransferring()

        let (outcome, model, ledger) = await signIn(
            after: .failed(RevenueCatPurchaseControllerError.entitlementUnconfirmed),
            transferring: transferring
        )

        #expect(outcome == .notTransferred)
        #expect(transferring.calls == ["refresh", "restore"])
        #expect(ledger.progress().pendingPurchase == nil)
        #expect(!model.isAwaitingConfirmation)
    }

    @Test
    func aCompletedSignInHasNothingToMoveForAnAskToBuy() async {
        let transferring = StubTransferring()

        let (outcome, model, ledger) = await signIn(after: .pending, transferring: transferring)

        #expect(outcome == .nothingToTransfer)
        #expect(transferring.calls.isEmpty)
        #expect(ledger.progress().pendingPurchase == nil)
        #expect(!model.isAwaitingConfirmation)
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
    func nothingCanBeBoughtByAnInstallThatAlreadyHoldsAccess() async {
        let provider = StubPlanProvider(plans: plans())
        let (model, _) = make(provider: provider, entitlement: .active(["app_access"]))
        await model.load()

        #expect(await model.purchaseSelectedPlan() == .notCompleted)
        #expect(provider.purchasedPlanIDs.isEmpty)
    }

    @Test
    func aRelaunchedLockHoldsEvenWhenThePlansCannotLoad() async {
        let provider = StubPlanProvider(plans: [])
        let ledger = PreAuthPurchaseLedger(
            userDefaults: UserDefaults(suiteName: "OnboardingPaywallModelTests-\(UUID().uuidString)")!
        )
        ledger.markPurchasePending(PreAuthPendingPurchase(productID: "yearly", hold: .unconfirmedCharge))
        let (model, _) = make(provider: provider, ledger: ledger)
        await model.load()

        #expect(model.loadState == .unavailable)
        #expect(model.isAwaitingConfirmation)
    }

    @Test
    func accessLandingAfterARelaunchClearsTheMarkerAndMovesToSignIn() async throws {
        let ledger = PreAuthPurchaseLedger(
            userDefaults: UserDefaults(suiteName: "OnboardingPaywallModelTests-\(UUID().uuidString)")!
        )
        ledger.markPaywallReached()
        ledger.markPurchasePending(PreAuthPendingPurchase(productID: "welcome", hold: .askToBuy))
        let service = EntitlementServiceStub(entitlementState: .inactive)
        let (model, _) = make(
            provider: StubPlanProvider(plans: plans()),
            entitlementService: service,
            ledger: ledger
        )
        await model.load()

        service.setEntitlementState(.active(["app_access"]))
        #expect(model.recordHeldAccess())

        #expect(!model.isAwaitingConfirmation)
        #expect(ledger.progress().pendingPurchase == nil)
        #expect(ledger.resumeStep == .auth)
        #expect(ledger.progress().purchase?.productID == "welcome")
    }

    @Test
    func aReleasedAskToBuyDoesNotComeBackOnRelaunch() async {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = .pending
        let (first, ledger) = make(provider: provider)
        await first.load()
        _ = await first.purchaseSelectedPlan()
        _ = await first.restore()

        let (relaunched, _) = make(provider: StubPlanProvider(plans: plans()), ledger: ledger)

        #expect(ledger.progress().pendingPurchase == nil)
        #expect(!relaunched.isAwaitingConfirmation)
    }

    @Test
    func aCancelledOrFailedPurchaseLeavesNoMarker() async {
        let provider = StubPlanProvider(plans: plans())
        let (model, ledger) = make(provider: provider)
        await model.load()

        provider.purchaseResult = .cancelled
        _ = await model.purchaseSelectedPlan()
        #expect(ledger.progress().pendingPurchase == nil)

        provider.purchaseResult = .failed(RevenueCatPurchaseControllerError.missingStoreKitProduct)
        _ = await model.purchaseSelectedPlan()
        #expect(ledger.progress().pendingPurchase == nil)
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

    @Test
    func aRestoreThatFindsTheUnconfirmedChargeRecordsThatPlan() async throws {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = .failed(RevenueCatPurchaseControllerError.entitlementUnconfirmed)
        let service = EntitlementServiceStub(entitlementState: .inactive)
        service.restoredState = .active(["app_access"])
        let (model, ledger) = make(provider: provider, entitlementService: service)
        await model.load()
        _ = await model.claimGift()

        #expect(await model.restore() == .restored)

        let purchase = try #require(ledger.progress().purchase)
        #expect(purchase.source == .purchase)
        #expect(purchase.productID == "welcome")
        #expect(purchase.startedTrial)
        #expect(!model.isAwaitingConfirmation)
    }

    @Test
    func noAccessRecordsNothing() async {
        let provider = StubPlanProvider(plans: plans())
        provider.purchaseResult = .pending
        let (model, ledger) = make(provider: provider)
        await model.load()
        _ = await model.claimGift()

        #expect(!model.recordHeldAccess())
        #expect(ledger.resumeStep == nil)
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

// MARK: - The transfer after sign-in

@MainActor
private final class StubTransferring: PreAuthPurchaseTransferring {
    var refreshedActive = false
    var restoredActive = false
    private(set) var calls: [String] = []

    func refreshedEntitlementIsActive() async -> Bool {
        calls.append("refresh")
        return refreshedActive
    }

    func restoredEntitlementIsActive() async -> Bool {
        calls.append("restore")
        return restoredActive
    }
}

@MainActor
private final class StubInvoker: AppAccessReconciliationInvoking {
    var outcomes: [AppAccessReconciliationOutcome]
    var calls = 0

    init(_ outcomes: [AppAccessReconciliationOutcome]) { self.outcomes = outcomes }

    func invokeReconciliation() async throws -> AppAccessReconciliationOutcome {
        defer { calls += 1 }
        return outcomes[min(calls, outcomes.count - 1)]
    }
}

@MainActor
@Suite
struct PreAuthPurchaseTransferTests {
    private func make(
        bought: Bool,
        transferring: StubTransferring,
        invoker: StubInvoker
    ) -> (PreAuthPurchaseTransfer, PreAuthPurchaseLedger) {
        let ledger = PreAuthPurchaseLedger(
            userDefaults: UserDefaults(suiteName: "PreAuthPurchaseTransferTests-\(UUID().uuidString)")!
        )
        if bought {
            ledger.recordPurchase(PreAuthPurchase(productID: "y", purchasedAt: Date(), startedTrial: false))
        }
        let transfer = PreAuthPurchaseTransfer(
            ledger: ledger,
            monetization: transferring,
            invoker: invoker,
            maxAttempts: 3,
            retryDelay: .zero,
            sleep: { _ in },
            releaseUnconfirmedPurchase: {}
        )
        return (transfer, ledger)
    }

    @Test
    func nothingBoughtMeansNothingToTransfer() async {
        let transferring = StubTransferring()
        let invoker = StubInvoker([.active])
        let (transfer, _) = make(bought: false, transferring: transferring, invoker: invoker)

        #expect(await transfer.completeAfterSignIn() == .nothingToTransfer)
        #expect(transferring.calls.isEmpty)
        #expect(invoker.calls == 0)
    }

    @Test
    func aPurchaseThatFollowedTheLogInIsGrantedAndForgotten() async {
        let transferring = StubTransferring()
        transferring.refreshedActive = true
        let invoker = StubInvoker([.active])
        let (transfer, ledger) = make(bought: true, transferring: transferring, invoker: invoker)

        #expect(await transfer.completeAfterSignIn() == .granted)
        #expect(transferring.calls == ["refresh"])
        #expect(ledger.progress() == PreAuthPaywallProgress())
    }

    @Test
    func anAccountRevenueCatAlreadyKnewIsRestoredOnceToMoveThePurchase() async {
        let transferring = StubTransferring()
        transferring.restoredActive = true
        let invoker = StubInvoker([.active])
        let (transfer, _) = make(bought: true, transferring: transferring, invoker: invoker)

        #expect(await transfer.completeAfterSignIn() == .granted)
        #expect(transferring.calls == ["refresh", "restore"])
    }

    @Test
    func aPurchaseThatNeverReachedTheAccountIsLeftToThePaywallAfterSignIn() async {
        let transferring = StubTransferring()
        let invoker = StubInvoker([.active])
        let (transfer, ledger) = make(bought: true, transferring: transferring, invoker: invoker)

        #expect(await transfer.completeAfterSignIn() == .notTransferred)
        #expect(invoker.calls == 0)
        #expect(ledger.progress().purchase != nil)
    }

    @Test
    func theWaitStopsAtAThrottledServerAndClaimsNothingAboutTheGrant() async {
        let transferring = StubTransferring()
        transferring.refreshedActive = true
        let invoker = StubInvoker([.throttled, .active])
        let (transfer, _) = make(bought: true, transferring: transferring, invoker: invoker)

        #expect(await transfer.completeAfterSignIn() == .grantUnconfirmed)
        #expect(invoker.calls == 1)
    }

    @Test
    func theWaitRemembersAnInactiveAnswerAcrossTheThrottleThatFollowsIt() async {
        let transferring = StubTransferring()
        transferring.refreshedActive = true
        let invoker = StubInvoker([.inactive, .throttled])
        let (transfer, _) = make(bought: true, transferring: transferring, invoker: invoker)

        #expect(await transfer.completeAfterSignIn() == .grantPending)
        #expect(invoker.calls == 2)
    }

    @Test
    func theWaitAsksAgainAfterAnAnswerItCouldNotRead() async {
        let transferring = StubTransferring()
        transferring.refreshedActive = true
        let invoker = StubInvoker([.unrecognized, .active])
        let (transfer, _) = make(bought: true, transferring: transferring, invoker: invoker)

        #expect(await transfer.completeAfterSignIn() == .granted)
        #expect(invoker.calls == 2)
    }

    @Test
    func aServerThatNeverAnswersEndsTheWaitWithoutLosingTheAccess() async {
        let transferring = StubTransferring()
        transferring.refreshedActive = true
        let invoker = StubInvoker([.unrecognized])
        let (transfer, ledger) = make(bought: true, transferring: transferring, invoker: invoker)

        #expect(await transfer.completeAfterSignIn() == .grantPending)
        #expect(invoker.calls == 3)
        #expect(ledger.progress().purchase != nil)
    }
}

// MARK: - The welcome product and anonymous purchase

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
        #expect(configuration.preAuthProductIDs == ["ascend_yearly", "ascend_lifetime", "ascend_yearly_welcome"])
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

        let preAuth = NativePaywallPlanMapper.plans(
            from: products, eligibilityByProductID: ["w": .eligible],
            yearlyProductID: "y", lifetimeProductID: "l", welcomeProductID: "w",
            locale: Locale(identifier: "en_US")
        )
        #expect(preAuth.map(\.id) == ["y", "w"])
        #expect(preAuth.last?.title == "Annual")
        #expect(preAuth.last?.freeTrialPeriod == NativeSubscriptionPeriod(value: 1, unit: .week))
        #expect(preAuth.last?.price == 9.99)

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
struct AnonymousPurchaseTests {
    private func executor(allowsAnonymous: Bool, identity: MonetizationIdentityTransition?) -> RevenueCatPurchaseExecutor {
        RevenueCatPurchaseExecutor(
            transactionContextStore: PaywallTransactionContextStore(),
            entitlementID: "app_access",
            allowsAnonymousPurchase: allowsAnonymous,
            applySubscriptionStatus: { _ in },
            refreshEntitlementState: { .refreshed(.unknown) },
            currentIdentityGeneration: { identity },
            adoptEntitlementState: { _, _ in true }
        )
    }

    private let anonymous = MonetizationIdentityTransition(revision: 3, userID: nil)

    @Test
    func theSignedInGateStillRefusesAPurchaseWithNoUid() async {
        var ran = false
        let result = await executor(allowsAnonymous: false, identity: anonymous).executePurchase(productID: "y") {
            ran = true
            return .init(userCancelled: false, entitlementState: .active(["app_access"]))
        }

        #expect(!ran)
        guard case .failed = result else { Issue.record("expected a refusal"); return }
    }

    @Test
    func thePreSignInPaywallBuysAsTheAnonymousCustomer() async {
        let result = await executor(allowsAnonymous: true, identity: anonymous).executePurchase(productID: "y") {
            .init(userCancelled: false, entitlementState: .active(["app_access"]))
        }

        guard case .purchased = result else { Issue.record("expected a purchase, got \(result)"); return }
    }

    @Test
    func noIdentityAtAllStillRefusesEvenForThePreSignInPaywall() async {
        var ran = false
        let result = await executor(allowsAnonymous: true, identity: nil).executePurchase(productID: "y") {
            ran = true
            return .init(userCancelled: false, entitlementState: .active(["app_access"]))
        }

        #expect(!ran)
        guard case .failed = result else { Issue.record("expected a refusal"); return }
    }
}
