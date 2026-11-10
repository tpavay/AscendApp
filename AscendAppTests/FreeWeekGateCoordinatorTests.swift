import Foundation
import enum SuperwallKit.PurchaseResult
import Testing
@testable import AscendApp

/// What the app-access gate does when a climber closes the last paid offer without buying.
///
/// The dead end this replaces: a second decline used to land on the native plan picker, whose only
/// other ways out were deleting the account or signing out.
@MainActor
@Suite(.serialized)
struct FreeWeekGateCoordinatorTests {
    // MARK: - A climber who has never had their week

    @Test
    func decliningEveryPaidOfferOpensTheFounderLetterAndNeverThePlanPicker() async {
        let harness = await makeHarness()

        declinePaidOffers(harness)

        #expect(harness.presenter.placements == [.appAccessGate, .founderLetter])
        #expect(harness.coordinator.phase == .openingLetter)
        #expect(harness.provider.loadCount == 0)
        #expect(harness.coordinator.showsPurchaseControls == false)
        #expect(harness.presenter.params(at: 1)?["source"] as? String == "paid_offers_declined")
    }

    @Test(arguments: [
        PaywallPresentationOutcome.dismissedWithoutPurchase,
        .backRequested
    ])
    func closingTheLetterStartsTheWeekAndOpensTheApp(closing: PaywallPresentationOutcome) async {
        let harness = await makeHarness()
        let week = harness.freeWeek.week()
        harness.freeWeek.granter.responses = [.success(.granted(week))]

        declinePaidOffers(harness)
        harness.presenter.send(.presented, registration: 1)
        #expect(harness.coordinator.phase == .letterPresented)
        #expect(harness.freeWeek.granter.callCount == 0)

        harness.presenter.send(closing, registration: 1)
        #expect(harness.coordinator.phase == .startingFreeWeek)
        #expect(await freeWeekWaitUntil { harness.coordinator.phase == .accessConfirmed })

        #expect(harness.freeWeek.granter.callCount == 1)
        #expect(harness.freeWeek.store.routingAccess == .live)
        #expect(harness.manager.hasAppAccess)
        #expect(harness.provider.loadCount == 0)
        #expect(harness.eventNames == [
            "free_week_letter_shown",
            "free_week_granted"
        ])
        #expect(harness.event("free_week_letter_shown")?.parameters["flow_version"] == .string("v3"))
        #expect(harness.event("free_week_granted")?.parameters["flow_version"] == .string("v3"))
        #expect(harness.event("free_week_granted")?.parameters["letter_shown"] == .bool(true))
    }

    @Test(arguments: [
        PaywallPresentationOutcome.skipped(reason: "no_audience_match"),
        .failed(message: "Plans could not open.")
    ])
    func aLetterSuperwallCannotPresentStillGrantsTheWeek(outcome: PaywallPresentationOutcome) async {
        let harness = await makeHarness()
        harness.freeWeek.granter.responses = [.success(.granted(harness.freeWeek.week()))]

        declinePaidOffers(harness)
        harness.presenter.send(outcome, registration: 1)

        #expect(await freeWeekWaitUntil { harness.coordinator.phase == .accessConfirmed })
        #expect(harness.freeWeek.store.routingAccess == .live)
        #expect(harness.provider.loadCount == 0)
        #expect(harness.eventNames == ["free_week_granted"])
        #expect(harness.event("free_week_granted")?.parameters["letter_shown"] == .bool(false))
    }

    @Test
    func aLetterThatNeverOpensIsNotWaitedOnPastItsDeadline() async {
        let deadline = FreeWeekDeadline()
        let harness = await makeHarness(sleep: deadline.sleep)
        harness.freeWeek.granter.responses = [.success(.granted(harness.freeWeek.week()))]

        declinePaidOffers(harness)
        #expect(harness.coordinator.phase == .openingLetter)
        // Calls 1 and 2 guard the Lifetime paywall's opening and the welcome offer's; 3 is the letter's.
        await deadline.fire(call: 3)

        #expect(await freeWeekWaitUntil { harness.coordinator.phase == .accessConfirmed })
        #expect(harness.presenter.cancelCount == 1)
        #expect(harness.freeWeek.store.routingAccess == .live)
    }

    @Test
    func aGrantThatFailsTwiceFallsThroughToThePlanPickerWithItsMessage() async {
        let harness = await makeHarness()
        harness.freeWeek.granter.responses = [.failure(FreeWeekTestError())]

        declinePaidOffers(harness)
        harness.presenter.send(.dismissedWithoutPurchase, registration: 1)

        #expect(await freeWeekWaitUntil { harness.coordinator.phase == .nativeReady })
        // One call and one retry, and then the climber is given something to tap.
        #expect(harness.freeWeek.granter.callCount == 2)
        #expect(harness.provider.loadCount == 1)
        #expect(harness.coordinator.showsPurchaseControls)
        #expect(harness.coordinator.plans.isEmpty == false)
        #expect(harness.freeWeek.store.routingAccess == .none)
        #expect(harness.eventNames.contains("free_week_granted") == false)
    }

    @Test
    func aChainedScreenAfterTheLetterIsWaitedForBeforeTheWeekStarts() async {
        let harness = await makeHarness()
        harness.freeWeek.granter.responses = [.success(.granted(harness.freeWeek.week()))]

        declinePaidOffers(harness)
        harness.presenter.send(.presented, registration: 1)
        harness.presenter.send(.followOnPaywallOpening, registration: 1)
        #expect(harness.coordinator.phase == .openingLetter)
        #expect(harness.freeWeek.granter.callCount == 0)

        harness.presenter.send(.presented, registration: 1)
        harness.presenter.send(.dismissedWithoutPurchase, registration: 1)

        #expect(await freeWeekWaitUntil { harness.coordinator.phase == .accessConfirmed })
        #expect(harness.eventNames.filter { $0 == "free_week_letter_shown" }.count == 1)
    }

    // MARK: - A climber whose week is over

    @Test
    func aSpentWeekGetsThePaywallAgainAndNeverTheLetterOrThePicker() async {
        let harness = await makeHarness(spentWeek: true)

        harness.coordinator.start()
        harness.presenter.send(.presented, registration: 0)
        harness.presenter.send(.followOnPaywallOpening, registration: 0)
        harness.presenter.send(.presented, registration: 0)
        harness.presenter.send(.dismissedWithoutPurchase, registration: 0)

        // Lifetime paywall, decline, gift offer, decline, Lifetime paywall again.
        #expect(harness.presenter.placements == [.appAccessGate, .appAccessGate])
        #expect(harness.presenter.params(at: 1)?["source"] as? String == "free_week_ended")
        #expect(harness.coordinator.phase == .openingHosted)
        #expect(harness.provider.loadCount == 0)
        #expect(harness.freeWeek.granter.callCount == 0)

        // And the floor holds for as long as the climber keeps declining.
        harness.presenter.send(.presented, registration: 1)
        harness.presenter.send(.dismissedWithoutPurchase, registration: 1)
        #expect(harness.presenter.placements == [.appAccessGate, .appAccessGate, .appAccessGate])
        #expect(harness.provider.loadCount == 0)
    }

    @Test
    func theGateReportsAWeekThatEndedOncePerAccount() async {
        let harness = await makeHarness(spentWeek: true)

        harness.coordinator.start()
        #expect(harness.eventNames == ["free_week_expired_gated"])
        #expect(harness.event("free_week_expired_gated")?.parameters["flow_version"] == .string("v3"))

        harness.coordinator.retryHosted()
        harness.coordinator.cancelOwnedWork()
        #expect(harness.eventNames == ["free_week_expired_gated"])
    }

    @Test
    func aPaywallThatClosesWithoutEverOpeningDoesNotLoopOnTheFloor() async {
        let harness = await makeHarness(spentWeek: true)

        harness.coordinator.start()
        harness.presenter.send(.dismissedWithoutPurchase, registration: 0)

        #expect(await freeWeekWaitUntil { harness.coordinator.phase == .nativeReady })
        #expect(harness.presenter.placements == [.appAccessGate])
    }

    @Test
    func theServerSayingTheWeekIsSpentPutsTheClimberBackOnThePaywall() async {
        let harness = await makeHarness()
        harness.freeWeek.granter.responses = [
            .success(.alreadyUsed(harness.freeWeek.week(startingDaysAgo: 30)))
        ]

        declinePaidOffers(harness)
        harness.presenter.send(.dismissedWithoutPurchase, registration: 1)

        #expect(await freeWeekWaitUntil { harness.presenter.placements.count == 3 })
        #expect(harness.presenter.placements.last == .appAccessGate)
        #expect(harness.provider.loadCount == 0)
        #expect(harness.freeWeek.store.hasSpentWeek)
    }

    // MARK: - What still reaches the plan picker

    @Test
    func aPaywallSuperwallCouldNotPresentStillFallsBackToThePlanPicker() async {
        let harness = await makeHarness()

        harness.coordinator.start()
        harness.presenter.send(.skipped(reason: "test"), registration: 0)

        #expect(await freeWeekWaitUntil { harness.coordinator.phase == .nativeReady })
        #expect(harness.presenter.placements == [.appAccessGate])
        #expect(harness.freeWeek.granter.callCount == 0)
    }

    @Test
    func withTheSwitchOffADeclineIsThePlanPickerExactlyAsBefore() async {
        let harness = await makeHarness(isEnabled: false)

        declinePaidOffers(harness)

        #expect(await freeWeekWaitUntil { harness.coordinator.phase == .nativeReady })
        #expect(harness.presenter.placements == [.appAccessGate])
        #expect(harness.coordinator.statusMessage?.contains("Choose from") == true)
        #expect(harness.freeWeek.granter.callCount == 0)
        #expect(harness.freeWeek.reader.readCount == 0)
        #expect(harness.eventNames.isEmpty)
    }

    @Test
    func aRecordThatCannotBeReadGetsThePickerRatherThanAPromiseItMayNotKeep() async {
        let harness = await makeHarness(record: .failure(FreeWeekTestError()))

        declinePaidOffers(harness)

        #expect(await freeWeekWaitUntil { harness.coordinator.phase == .nativeReady })
        #expect(harness.presenter.placements == [.appAccessGate])
        #expect(harness.freeWeek.granter.callCount == 0)
    }

    @Test
    func aPendingChargeIsToldToWaitAndIsNotOfferedAWeekOnTop() async {
        let harness = await makeHarness()
        harness.coordinator.start()
        harness.presenter.send(.presented, registration: 0)
        harness.manager.holdPendingPurchase(.unconfirmedCharge)

        harness.presenter.send(.dismissedWithoutPurchase, registration: 0)

        #expect(harness.coordinator.phase == .verificationUnavailable)
        #expect(harness.presenter.placements == [.appAccessGate])
        #expect(harness.freeWeek.granter.callCount == 0)
    }

    // MARK: - Paying during the week

    @Test
    func aPurchaseWhileTheWeekRunsIsReportedAsTheWeekConverting() async {
        let harness = await makeHarness(runningWeekDaysAgo: 2)
        let identity = MonetizationIdentityTransition(revision: 1, userID: "user-a")

        harness.manager.adoptPurchaseEntitlementState(.active(["app_access"]), for: identity)

        #expect(harness.eventNames == ["free_week_purchase_completed"])
        let event = harness.event("free_week_purchase_completed")
        #expect(event?.parameters["days_left"] == .int(5))
        #expect(event?.parameters["flow_version"] == .string("v3"))
    }

    /// The pass that led to the gate completes the moment the week lands, and a completed pass
    /// reports the legacy flow. The week's own events must not inherit that.
    @Test
    func theWeeksLaterEventsKeepTheFlowThatStartedIt() async {
        let harness = await makeHarness()
        harness.freeWeek.granter.responses = [.success(.granted(harness.freeWeek.week()))]
        let identity = MonetizationIdentityTransition(revision: 1, userID: "user-a")
        declinePaidOffers(harness)
        harness.presenter.send(.dismissedWithoutPurchase, registration: 1)
        #expect(await freeWeekWaitUntil { harness.coordinator.phase == .accessConfirmed })

        harness.lifecycle.recordFlowCompletedIfNeeded(reason: .freeWeek)
        #expect(harness.manager.onboardingFlowVersion == OnboardingAnalyticsContext.legacyFlowVersion)

        harness.manager.adoptPurchaseEntitlementState(.active(["app_access"]), for: identity)
        #expect(
            harness.event("free_week_purchase_completed")?.parameters["flow_version"] == .string("v3")
        )

        harness.freeWeek.clock.advance(days: 8)
        harness.freeWeek.store.reevaluate()
        harness.coordinator.cancelOwnedWork()
        let manager = harness.manager
        let returning = AppAccessPaywallCoordinator(
            monetizationManager: manager,
            nativeProvider: harness.provider,
            restoreService: AppAccessRestoreService(
                telemetry: harness.telemetry,
                entitlementID: "app_access",
                restorer: { manager }
            ),
            telemetry: harness.telemetry
        )
        returning.start()
        #expect(harness.event("free_week_expired_gated")?.parameters["flow_version"] == .string("v3"))
        returning.cancelOwnedWork()
    }

    @Test
    func aLetInClimberCompletesOnboardingAsAFreeWeekNotASale() async {
        let harness = await makeHarness(runningWeekDaysAgo: 0)

        #expect(harness.manager.onboardingCompletionReasonForActiveAccess == .freeWeek)
        #expect(OnboardingFlowCompletionReason.freeWeek.rawValue == "free_week")

        let none = await makeHarness()
        #expect(none.manager.onboardingCompletionReasonForActiveAccess == nil)
    }

    @Test
    func aPurchaseWithNoWeekRunningIsNotAConversion() async {
        let harness = await makeHarness()
        let identity = MonetizationIdentityTransition(revision: 1, userID: "user-a")

        harness.manager.adoptPurchaseEntitlementState(.active(["app_access"]), for: identity)

        #expect(harness.eventNames.isEmpty)
    }

    // MARK: - Harness

    private func declinePaidOffers(_ harness: FreeWeekGateHarness) {
        harness.coordinator.start()
        harness.presenter.send(.presented, registration: 0)
        // The Lifetime paywall closes for the gift offer, and then the gift offer is declined.
        harness.presenter.send(.followOnPaywallOpening, registration: 0)
        harness.presenter.send(.presented, registration: 0)
        harness.presenter.send(.dismissedWithoutPurchase, registration: 0)
    }

    private func makeHarness(
        isEnabled: Bool = true,
        record: Result<FreeWeekGrant?, any Error> = .success(nil),
        spentWeek: Bool = false,
        runningWeekDaysAgo: Double? = nil,
        sleep: @escaping AppAccessPaywallCoordinator.Sleep = { try await Task.sleep(for: $0) }
    ) async -> FreeWeekGateHarness {
        let identity = MonetizationIdentityTransition(revision: 1, userID: "user-a")
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = TelemetryManager(
            sinks: [sink],
            crashlyticsReporter: NoopCrashlyticsReporter(),
            collectionEnabledOverride: true,
            identityStore: makeTestIdentityStore()
        )
        telemetry.configure()
        telemetry.setUserId("user-a")

        let freeWeek = FreeWeekTestHarness(isEnabled: isEnabled, record: record)
        if spentWeek {
            freeWeek.cache.store(freeWeek.week(startingDaysAgo: 9), for: "user-a")
        }
        if let runningWeekDaysAgo {
            freeWeek.cache.store(freeWeek.week(startingDaysAgo: runningWeekDaysAgo), for: "user-a")
        }
        freeWeek.store.setUser("user-a")
        if isEnabled {
            _ = await freeWeekWaitUntil { freeWeek.store.record != .unknown }
        }

        let userDefaults = UserDefaults(suiteName: "FreeWeekGateCoordinatorTests-\(UUID().uuidString)")!
        // The pass that led to the gate is the 1.3.0 onboarding.
        let lifecycle = OnboardingFlowAnalyticsCoordinator(
            userDefaults: userDefaults,
            telemetry: telemetry
        )
        lifecycle.recordFlowStartedIfNeeded(
            context: OnboardingAnalyticsContext(
                segmentID: "pre_auth_welcome",
                flowVersion: OnboardingAnalyticsContext.currentFlowVersion,
                stepID: "welcome"
            )
        )

        let presenter = FreeWeekGatePresenter()
        let provider = FreeWeekGateNativeProvider()
        let manager = MonetizationManager(
            configuration: MonetizationConfiguration(
                infoDictionary: [
                    MonetizationConfiguration.revenueCatAPIKeyInfoKey: "appl_test",
                    MonetizationConfiguration.superwallAPIKeyInfoKey: "pk_test",
                    MonetizationConfiguration.revenueCatYearlyProductIDInfoKey: "ascend_staging_yearly",
                    MonetizationConfiguration.revenueCatLifetimeProductIDInfoKey: "ascend_staging_lifetime",
                    MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "NO"
                ]
            ),
            entitlementService: FreeWeekGateEntitlementService(identity: identity),
            paywallPresenter: presenter,
            appAccessReconciler: FreeWeekGateReconciler(),
            freeWeek: freeWeek.store,
            telemetry: telemetry,
            onboardingLifecycle: lifecycle,
            userDefaults: userDefaults
        )
        let coordinator = AppAccessPaywallCoordinator(
            monetizationManager: manager,
            nativeProvider: provider,
            restoreService: AppAccessRestoreService(
                telemetry: telemetry,
                entitlementID: "app_access",
                restorer: { manager }
            ),
            telemetry: telemetry,
            sleep: sleep
        )
        return FreeWeekGateHarness(
            coordinator: coordinator,
            manager: manager,
            presenter: presenter,
            provider: provider,
            freeWeek: freeWeek,
            sink: sink,
            telemetry: telemetry,
            lifecycle: lifecycle
        )
    }
}

@MainActor
private struct FreeWeekGateHarness {
    let coordinator: AppAccessPaywallCoordinator
    let manager: MonetizationManager
    let presenter: FreeWeekGatePresenter
    let provider: FreeWeekGateNativeProvider
    let freeWeek: FreeWeekTestHarness
    let sink: InMemoryTelemetrySink
    let telemetry: TelemetryManager
    let lifecycle: OnboardingFlowAnalyticsCoordinator

    /// The free week's own events, in order.
    var eventNames: [String] {
        sink.records.map(\.name).filter { $0.hasPrefix("free_week_") }
    }

    func event(_ name: String) -> EnvelopedTelemetryRecord? {
        sink.records.first { $0.name == name }
    }
}

@MainActor
private final class FreeWeekGatePresenter: PaywallPresenting {
    let isConfigured = true
    private(set) var cancelCount = 0
    private(set) var placements: [SuperwallPlacement] = []
    private var registeredParams: [[String: Any]?] = []
    private var handlers: [@MainActor (PaywallPresentationOutcome) -> Void] = []

    func configure(configuration: MonetizationConfiguration) {}
    func identify(userId: String) {}
    func resetIdentity() {}
    func cancelPresentation() { cancelCount += 1 }

    func register(
        placement: SuperwallPlacement,
        params: [String: Any]?,
        onOutcome: @escaping @MainActor (PaywallPresentationOutcome) -> Void
    ) {
        placements.append(placement)
        registeredParams.append(params)
        handlers.append(onOutcome)
    }

    func params(at registration: Int) -> [String: Any]? {
        registeredParams.indices.contains(registration) ? registeredParams[registration] : nil
    }

    func send(_ outcome: PaywallPresentationOutcome, registration: Int) {
        guard handlers.indices.contains(registration) else { return }
        handlers[registration](outcome)
    }
}

@MainActor
private final class FreeWeekGateNativeProvider: NativePaywallPlanProviding {
    private(set) var loadCount = 0

    func loadPlans() async throws -> [NativePaywallPlan] {
        loadCount += 1
        return [
            NativePaywallPlan(
                id: "ascend_staging_yearly",
                title: "Annual",
                localizedPrice: "$29.99",
                billingDescription: "Renews yearly.",
                trialDescription: nil
            ),
            NativePaywallPlan(
                id: "ascend_staging_lifetime",
                title: "Lifetime",
                localizedPrice: "$49.99",
                billingDescription: "Pay once. No renewal.",
                trialDescription: nil
            )
        ]
    }

    func purchase(planID: String) async -> PurchaseResult {
        .cancelled
    }
}

@MainActor
private final class FreeWeekGateEntitlementService: EntitlementServicing {
    var entitlementState: MonetizationEntitlementState = .inactive
    var hasFailedIdentityResolution = false
    var identityGeneration: MonetizationIdentityTransition?
    var isConfigured = true

    init(identity: MonetizationIdentityTransition) {
        identityGeneration = identity
    }

    func configure(configuration: MonetizationConfiguration) {}

    func refreshCustomerInfo(waitsForPendingIdentity: Bool) async -> MonetizationEntitlementRefresh {
        .refreshed(entitlementState)
    }

    func prepareIdentity(_ customer: MonetizationCustomerIdentity) -> MonetizationIdentityTransition {
        identityGeneration ?? MonetizationIdentityTransition(revision: 0, userID: customer.userID)
    }

    func identify(
        _ customer: MonetizationCustomerIdentity,
        transition: MonetizationIdentityTransition
    ) async {}

    func prepareIdentityReset() -> MonetizationIdentityTransition {
        MonetizationIdentityTransition(revision: 0, userID: nil)
    }

    func resetIdentity(transition: MonetizationIdentityTransition) async {}
    func retryIdentityResolution() async {}

    func adoptTransactionState(
        _ state: MonetizationEntitlementState,
        for identity: MonetizationIdentityTransition
    ) -> Bool {
        guard identityGeneration == identity else { return false }
        entitlementState = state
        return true
    }

    func restorePurchases(
        for identity: MonetizationIdentityTransition
    ) async -> MonetizationEntitlementState {
        entitlementState
    }

    func restorePurchases() async -> MonetizationEntitlementState {
        entitlementState
    }
}

@MainActor
private final class FreeWeekGateReconciler: AppAccessReconciling {
    func reconcileAppAccess(force: Bool) async {}
}

/// The gate's opening deadlines, fired by hand, numbered in the order the gate armed them.
private final class FreeWeekDeadline: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var callCount = 0

    var sleep: AppAccessPaywallCoordinator.Sleep {
        { [self] _ in
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                callCount += 1
                continuations[callCount] = continuation
                lock.unlock()
            }
        }
    }

    /// Waits for the gate to arm that deadline before firing it, on a wall clock: the task that
    /// arms it is the gate's own, and under the full suite's load it may not have run yet.
    func fire(call: Int) async {
        let clock = ContinuousClock()
        let giveUp = clock.now.advanced(by: .seconds(60))
        while clock.now < giveUp {
            if let continuation = take(call: call) {
                continuation.resume()
                return
            }
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    private func take(call: Int) -> CheckedContinuation<Void, any Error>? {
        lock.lock()
        defer { lock.unlock() }
        return continuations.removeValue(forKey: call)
    }
}
