import Foundation
import Testing
@testable import AscendApp

/// What the app-access gate does when a climber closes the last paid offer without buying.
///
/// Every outcome here ends on a hosted screen, in the app, or behind the spinner while the gate
/// asks the server again. The gate has no screen of its own to fall back to.
@MainActor
@Suite(.serialized)
struct FreeWeekGateCoordinatorTests {
    // MARK: - A climber who has never had their week

    @Test
    func decliningEveryPaidOfferOpensTheFounderLetter() async {
        let harness = await makeHarness()

        declinePaidOffers(harness)

        #expect(harness.presenter.placements == [.appAccessGate, .founderLetter])
        #expect(harness.coordinator.phase == .openingLetter)
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
        #expect(harness.eventNames == ["free_week_granted"])
        #expect(harness.event("free_week_granted")?.parameters["letter_shown"] == .bool(false))
    }

    @Test
    func aLetterThatNeverOpensIsNotWaitedOnPastItsDeadline() async {
        let harness = await makeHarness()
        harness.freeWeek.granter.responses = [.success(.granted(harness.freeWeek.week()))]

        declinePaidOffers(harness)
        #expect(harness.coordinator.phase == .openingLetter)
        // The paywall's and the welcome offer's deadlines were stood down when each opened, so
        // the one still running is the letter's.
        await harness.clock.fire(gateOpeningDeadline)

        #expect(await freeWeekWaitUntil { harness.coordinator.phase == .accessConfirmed })
        #expect(harness.presenter.cancelCount == 1)
        #expect(harness.freeWeek.store.routingAccess == .live)
    }

    @Test
    func aWeekThatCannotBeStartedIsAskedForAgainOnTheScheduleThenThePaywallReopens() async {
        let harness = await makeHarness()
        harness.freeWeek.granter.responses = [.failure(FreeWeekTestError())]

        declinePaidOffers(harness)
        harness.presenter.send(.dismissedWithoutPurchase, registration: 1)

        // Each attempt is the store's one call and one retry.
        #expect(await freeWeekWaitUntil { harness.freeWeek.granter.callCount == 2 })
        #expect(harness.coordinator.phase == .startingFreeWeek)
        await harness.clock.fire(.seconds(201))
        #expect(await freeWeekWaitUntil { harness.freeWeek.granter.callCount == 4 })
        #expect(harness.presenter.placements == [.appAccessGate, .founderLetter])
        await harness.clock.fire(.seconds(202))

        // The schedule is spent, and the climber is put back on a hosted screen - never on one of
        // the gate's own.
        #expect(await freeWeekWaitUntil { harness.presenter.placements.count == 3 })
        #expect(harness.freeWeek.granter.callCount == 6)
        #expect(harness.presenter.placements.last == .appAccessGate)
        #expect(harness.presenter.sources.last == "free_week_unavailable")
        #expect(harness.coordinator.phase == .openingHosted)
        #expect(harness.freeWeek.store.routingAccess == .none)
        #expect(harness.eventNames.contains("free_week_granted") == false)
    }

    @Test
    func aWeekThatStartsOnALaterAttemptOpensTheApp() async {
        let harness = await makeHarness()
        harness.freeWeek.granter.responses = [
            .failure(FreeWeekTestError()),
            .failure(FreeWeekTestError()),
            .success(.granted(harness.freeWeek.week()))
        ]

        declinePaidOffers(harness)
        harness.presenter.send(.dismissedWithoutPurchase, registration: 1)
        #expect(await freeWeekWaitUntil { harness.freeWeek.granter.callCount == 2 })
        await harness.clock.fire(.seconds(201))

        #expect(await freeWeekWaitUntil { harness.coordinator.phase == .accessConfirmed })
        #expect(harness.freeWeek.granter.callCount == 3)
        #expect(harness.freeWeek.store.routingAccess == .live)
        #expect(harness.presenter.placements == [.appAccessGate, .founderLetter])
        #expect(harness.clock.pending == [gateRouteDeadline])
    }

    @Test
    func theServerHoldingPaidAccessTheDeviceHasNotHeardOfIsCheckedBehindTheSpinner() async {
        let harness = await makeHarness()
        harness.freeWeek.granter.responses = [.success(.paidActive)]
        harness.entitlements.stateAfterRefresh = [2: .active(["app_access"])]

        declinePaidOffers(harness)
        harness.presenter.send(.dismissedWithoutPurchase, registration: 1)

        #expect(await freeWeekWaitUntil { harness.coordinator.phase == .confirmingAccess })
        await harness.clock.fire(.seconds(301))
        #expect(await freeWeekWaitUntil { harness.coordinator.phase == .accessConfirmed })
        #expect(harness.presenter.placements == [.appAccessGate, .founderLetter])
        #expect(harness.eventNames.contains("free_week_granted") == false)
    }

    /// A climber leaving the account is not accepting a week on it.
    @Test
    func aSignOutFromTheLetterSignsOutRatherThanStartingTheWeek() async {
        let harness = await makeHarness()
        harness.freeWeek.granter.responses = [.success(.granted(harness.freeWeek.week()))]

        declinePaidOffers(harness)
        harness.presenter.send(.presented, registration: 1)
        harness.presenter.send(.signOutRequested, registration: 1)

        #expect(harness.signOut.count == 1)
        #expect(harness.coordinator.phase != .startingFreeWeek)
        #expect(harness.freeWeek.granter.callCount == 0)
        #expect(harness.freeWeek.store.routingAccess == .none)
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
    func aSpentWeekGetsThePaywallAgainAndNeverTheLetter() async {
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
        #expect(harness.freeWeek.granter.callCount == 0)

        // And the floor holds for as long as the climber keeps declining.
        harness.presenter.send(.presented, registration: 1)
        harness.presenter.send(.dismissedWithoutPurchase, registration: 1)
        #expect(harness.presenter.placements == [.appAccessGate, .appAccessGate, .appAccessGate])
    }

    /// Declining the floor only reopens it, so the floor's own Sign out is how a climber on the
    /// wrong account leaves it without deleting it.
    @Test
    func aSignOutFromTheFloorSignsOutAndDoesNotReopenThePaywall() async {
        let harness = await makeHarness(spentWeek: true)

        harness.coordinator.start()
        harness.presenter.send(.presented, registration: 0)
        harness.presenter.send(.dismissedWithoutPurchase, registration: 0)
        #expect(harness.presenter.placements == [.appAccessGate, .appAccessGate])

        harness.presenter.send(.presented, registration: 1)
        harness.presenter.send(.signOutRequested, registration: 1)

        #expect(harness.signOut.count == 1)
        #expect(harness.presenter.placements == [.appAccessGate, .appAccessGate])
        #expect(harness.freeWeek.granter.callCount == 0)
        let terminals = harness.sink.records.filter { $0.name == "app_access_gate_attempt_terminal" }
        #expect(terminals.last?.parameters["provider_outcome"] == .string("sign_out_requested"))
        #expect(terminals.last?.parameters["recovery_reason"] == .string("hosted_sign_out_requested"))
    }

    @Test
    func theGateReportsAWeekThatEndedOncePerAccount() async {
        let harness = await makeHarness(spentWeek: true)

        harness.coordinator.start()
        #expect(harness.eventNames == ["free_week_expired_gated"])
        #expect(harness.event("free_week_expired_gated")?.parameters["flow_version"] == .string("v3"))

        // The gate starting over - here for a refreshed identity - is not a second week ending.
        harness.coordinator.identityDidChange()
        harness.coordinator.cancelOwnedWork()
        #expect(harness.eventNames == ["free_week_expired_gated"])
    }

    @Test
    func aPaywallThatClosesWithoutEverOpeningDoesNotLoopOnTheFloor() async {
        let harness = await makeHarness(spentWeek: true)

        harness.coordinator.start()
        harness.presenter.send(.dismissedWithoutPurchase, registration: 0)

        // Nobody tapped anything, so reopening at once would be a loop. It waits out the backoff
        // like any other paywall that could not open.
        #expect(harness.coordinator.phase == .awaitingHostedRetry)
        #expect(harness.presenter.placements == [.appAccessGate])
        await harness.clock.fire(.seconds(101))
        #expect(await freeWeekWaitUntil { harness.presenter.placements.count == 2 })
        #expect(harness.presenter.sources.last == "presentation_retry")
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
        #expect(harness.freeWeek.store.hasSpentWeek)
    }

    // MARK: - What gets the paywall instead of the week

    @Test
    func aPaywallSuperwallCouldNotPresentIsNotADeclineAndGrantsNothing() async {
        let harness = await makeHarness()

        harness.coordinator.start()
        harness.presenter.send(.skipped(reason: "test"), registration: 0)

        #expect(harness.coordinator.phase == .awaitingHostedRetry)
        #expect(harness.presenter.placements == [.appAccessGate])
        #expect(harness.freeWeek.granter.callCount == 0)
    }

    @Test
    func withTheSwitchOffADeclineReopensThePaywallAndTheWeekStaysDark() async {
        let harness = await makeHarness(isEnabled: false)

        declinePaidOffers(harness)

        #expect(harness.presenter.placements == [.appAccessGate, .appAccessGate])
        #expect(harness.presenter.sources.last == "paid_offers_declined")
        #expect(harness.coordinator.phase == .openingHosted)
        #expect(harness.freeWeek.granter.callCount == 0)
        #expect(harness.freeWeek.reader.readCount == 0)
        #expect(harness.eventNames.isEmpty)
        let terminals = harness.sink.records.filter { $0.name == "app_access_gate_attempt_terminal" }
        #expect(terminals.map { $0.parameters["provider_outcome"] } == [.string("paywall_floor")])
        #expect(terminals.first?.parameters["recovery_reason"] == .string("hosted_dismissed"))

        // And it keeps reopening for as long as the climber keeps declining.
        harness.presenter.send(.presented, registration: 1)
        harness.presenter.send(.dismissedWithoutPurchase, registration: 1)
        #expect(harness.presenter.placements == [.appAccessGate, .appAccessGate, .appAccessGate])
    }

    @Test
    func aRecordThatCannotBeReadIsAskedForAgainThenGetsThePaywallRatherThanAPromiseItMayNotKeep() async {
        let harness = await makeHarness(record: .failure(FreeWeekTestError()))
        let readsBeforeDecline = harness.freeWeek.reader.readCount

        declinePaidOffers(harness)

        #expect(harness.coordinator.phase == .startingFreeWeek)
        #expect(await freeWeekWaitUntil { harness.freeWeek.reader.readCount == readsBeforeDecline + 1 })
        await harness.clock.fire(.seconds(201))
        #expect(await freeWeekWaitUntil { harness.freeWeek.reader.readCount == readsBeforeDecline + 2 })
        await harness.clock.fire(.seconds(202))

        #expect(await freeWeekWaitUntil { harness.presenter.placements.count == 2 })
        #expect(harness.freeWeek.reader.readCount == readsBeforeDecline + 3)
        #expect(harness.presenter.placements == [.appAccessGate, .appAccessGate])
        #expect(harness.presenter.sources.last == "free_week_unavailable")
        #expect(harness.freeWeek.granter.callCount == 0)
        let terminals = harness.sink.records.filter { $0.name == "app_access_gate_attempt_terminal" }
        #expect(terminals.last?.parameters["provider_outcome"] == .string("paywall_floor"))
        #expect(terminals.last?.parameters["recovery_reason"] == .string("free_week_unavailable"))
    }

    @Test
    func aRecordThatAnswersOnALaterReadStillGetsTheLetter() async {
        let harness = await makeHarness(record: .failure(FreeWeekTestError()))
        let readsBeforeDecline = harness.freeWeek.reader.readCount

        declinePaidOffers(harness)
        #expect(await freeWeekWaitUntil { harness.freeWeek.reader.readCount == readsBeforeDecline + 1 })
        harness.freeWeek.reader.result = .success(nil)
        await harness.clock.fire(.seconds(201))

        #expect(await freeWeekWaitUntil { harness.presenter.placements.count == 2 })
        #expect(harness.presenter.placements == [.appAccessGate, .founderLetter])
        #expect(harness.coordinator.phase == .openingLetter)
    }

    @Test
    func aPendingChargeIsCheckedForAccessAndIsNotOfferedAWeekOnTop() async {
        let harness = await makeHarness()
        harness.coordinator.start()
        harness.presenter.send(.presented, registration: 0)
        harness.manager.holdPendingPurchase(.unconfirmedCharge)

        harness.presenter.send(.dismissedWithoutPurchase, registration: 0)

        #expect(harness.coordinator.phase == .confirmingAccess)
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
            telemetry: harness.telemetry,
            retryPolicy: .test,
            sleep: harness.clock.sleep
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
        runningWeekDaysAgo: Double? = nil
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

        let presenter = GateTestPresenter()
        let entitlements = GateTestEntitlementService(identity: identity)
        let clock = GateTestClock()
        let signOut = FreeWeekSignOutSpy()
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
            entitlementService: entitlements,
            paywallPresenter: presenter,
            appAccessReconciler: GateTestReconciler(),
            freeWeek: freeWeek.store,
            telemetry: telemetry,
            onboardingLifecycle: lifecycle,
            userDefaults: userDefaults
        )
        let coordinator = AppAccessPaywallCoordinator(
            monetizationManager: manager,
            telemetry: telemetry,
            onRequestSignOut: { signOut.count += 1 },
            retryPolicy: .test,
            sleep: clock.sleep
        )
        return FreeWeekGateHarness(
            coordinator: coordinator,
            manager: manager,
            presenter: presenter,
            entitlements: entitlements,
            clock: clock,
            signOut: signOut,
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
    let presenter: GateTestPresenter
    let entitlements: GateTestEntitlementService
    let clock: GateTestClock
    let signOut: FreeWeekSignOutSpy
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
private final class FreeWeekSignOutSpy {
    var count = 0
}
