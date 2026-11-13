import Foundation
@testable import SuperwallKit
import Testing
@testable import AscendApp

/// A climber who force-closes the app on the first paywall never reaches the decline offer (the
/// gift screen) the close would have opened, so the next launch opens it (`DeclineOfferReplayStore`).
///
/// A "launch" here is a new manager and gate over the same defaults: the marker is the only thing
/// that crosses it, exactly as it does between two processes.
@MainActor
@Suite(.serialized)
struct DeclineOfferReplayTests {
    // MARK: - The placement

    @Test
    func theReplayRegistersAPlacementTheSDKAcceptsFromAnApp() {
        // SuperwallKit drops a registration named after one of its own events without a callback,
        // which would leave the gate on its spinner until the watchdog gave up.
        let reservedNames = Set(SuperwallEventObjc.allCases.map(\.description))

        #expect(reservedNames.contains("paywall_decline"))
        #expect(!reservedNames.contains(SuperwallPlacement.declineOfferReplay.rawValue))
    }

    @Test(arguments: [SuperwallPlacement.declineOfferReplay.rawValue, "paywall_decline"])
    func theDeclineOfferIsNeverReportedByAscend(placement: String) {
        #expect(SuperwallPlacement(reportedByAscend: placement) == nil)
    }

    // MARK: - The marker

    @Test
    func theFirstPaywallReachingTheScreenMarksTheOfferAsOwed() async {
        let defaults = makeDefaults()
        let launch = await makeLaunch(defaults: defaults)
        #expect(DeclineOfferReplayStore(userDefaults: defaults).pendingUserID() == nil)

        launch.coordinator.start()
        #expect(DeclineOfferReplayStore(userDefaults: defaults).pendingUserID() == nil)
        launch.presenter.send(.presented, registration: 0)

        #expect(DeclineOfferReplayStore(userDefaults: defaults).pendingUserID() == "user-a")
    }

    @Test
    func theOfferTheSDKChainsOntoTheCloseClearsTheMarkerForGood() async {
        let defaults = makeDefaults()
        let launch = await makeLaunch(defaults: defaults)
        let store = DeclineOfferReplayStore(userDefaults: defaults)

        launch.coordinator.start()
        launch.presenter.send(.presented, registration: 0)
        launch.presenter.send(.followOnPaywallOpening, registration: 0)
        // Closing the paywall is not the offer: it is still owed until it is on the screen.
        #expect(store.pendingUserID() == "user-a")
        launch.presenter.send(.presented, registration: 0)

        #expect(store.pendingUserID() == nil)
        #expect(store.hasShown(for: "user-a"))
    }

    @Test(arguments: [Switch.freeWeek, .onboardingV3])
    func withEitherSwitchOffNothingIsRemembered(off: Switch) async {
        let defaults = makeDefaults()
        let launch = await makeLaunch(
            defaults: defaults,
            freeWeekEnabled: off != .freeWeek,
            onboardingV3Enabled: off != .onboardingV3
        )

        launch.coordinator.start()
        launch.presenter.send(.presented, registration: 0)

        #expect(DeclineOfferReplayStore(userDefaults: defaults).pendingUserID() == nil)
    }

    @Test
    func aClimberWhoDidNotWalkTheV3OnboardingIsNeverOwedTheOffer() async {
        let defaults = makeDefaults()
        let launch = await makeLaunch(defaults: defaults, walkedV3: false)

        launch.coordinator.start()
        launch.presenter.send(.presented, registration: 0)

        #expect(DeclineOfferReplayStore(userDefaults: defaults).pendingUserID() == nil)
    }

    // MARK: - The next launch

    @Test
    func aForceClosedFirstPaywallOpensTheOfferOnTheNextLaunch() async {
        let defaults = makeDefaults()
        let first = await makeLaunch(defaults: defaults)
        first.coordinator.start()
        first.presenter.send(.presented, registration: 0)
        // The app is killed here: nothing else of the first launch survives.

        let second = await makeLaunch(defaults: defaults)
        second.coordinator.start()

        #expect(second.presenter.placements == [.declineOfferReplay])
        #expect(second.presenter.sources == ["decline_offer_replay"])
        #expect(
            second.presenter.params(at: 0)?["presented_by_event_name"] as? String
                == SuperwallPlacement.appAccessGate.rawValue
        )
    }

    @Test
    func theReplayedOfferEndsInTheFounderLetterLikeTheChainedOne() async {
        let defaults = makeDefaults()
        let first = await makeLaunch(defaults: defaults)
        first.coordinator.start()
        first.presenter.send(.presented, registration: 0)

        let second = await makeLaunch(defaults: defaults)
        second.coordinator.start()
        second.presenter.send(.presented, registration: 0)
        #expect(second.coordinator.phase == .hostedPresented)
        second.presenter.send(.dismissedWithoutPurchase, registration: 0)

        #expect(second.presenter.placements == [.declineOfferReplay, .founderLetter])
    }

    @Test
    func aPurchaseOnTheReplayedOfferOpensTheApp() async {
        let defaults = makeDefaults()
        let first = await makeLaunch(defaults: defaults)
        first.coordinator.start()
        first.presenter.send(.presented, registration: 0)

        let second = await makeLaunch(defaults: defaults)
        second.coordinator.start()
        second.presenter.send(.presented, registration: 0)
        second.presenter.send(.purchased, registration: 0)

        #expect(second.coordinator.phase == .accessConfirmed)
        #expect(second.presenter.placements == [.declineOfferReplay])
    }

    // MARK: - Once

    @Test
    func theOfferIsNotReplayedAfterItHasBeenShown() async {
        let defaults = makeDefaults()
        let first = await makeLaunch(defaults: defaults)
        first.coordinator.start()
        first.presenter.send(.presented, registration: 0)

        let second = await makeLaunch(defaults: defaults)
        second.coordinator.start()
        second.presenter.send(.presented, registration: 0)
        // Killed again, on the offer this time.

        let third = await makeLaunch(defaults: defaults)
        third.coordinator.start()

        #expect(third.presenter.placements == [.appAccessGate])
    }

    @Test
    func theFirstPaywallAppearingAgainNeverOwesAnOfferThatWasShown() async {
        let defaults = makeDefaults()
        let first = await makeLaunch(defaults: defaults)
        first.coordinator.start()
        first.presenter.send(.presented, registration: 0)
        first.presenter.send(.followOnPaywallOpening, registration: 0)
        first.presenter.send(.presented, registration: 0)

        // The floor: the first paywall comes back after every paid offer is closed.
        let second = await makeLaunch(defaults: defaults)
        second.coordinator.start()
        second.presenter.send(.presented, registration: 0)

        #expect(DeclineOfferReplayStore(userDefaults: defaults).pendingUserID() == nil)
        let third = await makeLaunch(defaults: defaults)
        third.coordinator.start()
        #expect(third.presenter.placements == [.appAccessGate])
    }

    @Test
    func theReplayIsOnlyForTheLaunchAfterTheClose() async {
        let defaults = makeDefaults()
        let launch = await makeLaunch(defaults: defaults)
        launch.coordinator.start()
        launch.presenter.send(.presented, registration: 0)

        // The gate leaving the screen and coming back in the same process is not a force-close.
        launch.coordinator.cancelOwnedWork()
        launch.coordinator.start()

        #expect(launch.presenter.placements == [.appAccessGate, .appAccessGate])
    }

    @Test(arguments: [
        SuperwallSkipReasonCategory.holdout, .noAudienceMatch, .userSubscribed
    ])
    func anOfferSuperwallDeliberatelySkipsFallsBackToThePaywallAndIsNotOwedAgain(
        reason: SuperwallSkipReasonCategory
    ) async {
        let defaults = makeDefaults()
        let first = await makeLaunch(defaults: defaults)
        first.coordinator.start()
        first.presenter.send(.presented, registration: 0)

        let second = await makeLaunch(defaults: defaults)
        second.coordinator.start()
        second.presenter.send(.skipped(reason: reason.rawValue), registration: 0)

        #expect(second.presenter.placements == [.declineOfferReplay, .appAccessGate])
        #expect(second.presenter.sources == ["decline_offer_replay", "decline_offer_unavailable"])
        #expect(DeclineOfferReplayStore(userDefaults: defaults).hasShown(for: "user-a"))
        let third = await makeLaunch(defaults: defaults)
        third.coordinator.start()
        #expect(third.presenter.placements == [.appAccessGate])
    }

    @Test
    func anOfferNoCampaignTriggersYetFallsBackToThePaywallAndIsAskedForAgainNextLaunch() async {
        let defaults = makeDefaults()
        let first = await makeLaunch(defaults: defaults)
        first.coordinator.start()
        first.presenter.send(.presented, registration: 0)

        let second = await makeLaunch(defaults: defaults)
        second.coordinator.start()
        let reason = SuperwallSkipReasonCategory.classify(String(describing: PaywallSkippedReason.placementNotFound))
        second.presenter.send(.skipped(reason: reason.rawValue), registration: 0)

        #expect(second.presenter.placements == [.declineOfferReplay, .appAccessGate])
        #expect(!DeclineOfferReplayStore(userDefaults: defaults).hasShown(for: "user-a"))
        let third = await makeLaunch(defaults: defaults)
        third.coordinator.start()
        #expect(third.presenter.placements == [.declineOfferReplay])
    }

    @Test
    func theSDKsSkipReasonsClassifyIntoWhetherTheSkipWasDeliberate() {
        #expect(SuperwallSkipReasonCategory.classify(String(describing: PaywallSkippedReason.placementNotFound)) == .placementNotFound)
        #expect(SuperwallSkipReasonCategory.classify(String(describing: PaywallSkippedReason.noAudienceMatch)) == .noAudienceMatch)
        #expect(!SuperwallSkipReasonCategory.placementNotFound.isDeliberate)
        #expect(SuperwallSkipReasonCategory.noAudienceMatch.isDeliberate)
    }

    @Test
    func anOfferThatFailedToOpenFallsBackToThePaywallAndIsAskedForAgainNextLaunch() async {
        let defaults = makeDefaults()
        let first = await makeLaunch(defaults: defaults)
        first.coordinator.start()
        first.presenter.send(.presented, registration: 0)

        let second = await makeLaunch(defaults: defaults)
        second.coordinator.start()
        second.presenter.send(.failed(message: "Plans could not open."), registration: 0)
        #expect(second.presenter.placements == [.declineOfferReplay, .appAccessGate])

        let third = await makeLaunch(defaults: defaults)
        third.coordinator.start()
        #expect(third.presenter.placements == [.declineOfferReplay])
    }

    // MARK: - Nobody entitled is ever shown it

    @Test
    func aClimberWhoHasAccessByNowIsNeverShownTheOffer() async {
        let defaults = makeDefaults()
        let first = await makeLaunch(defaults: defaults)
        first.coordinator.start()
        first.presenter.send(.presented, registration: 0)

        let second = await makeLaunch(defaults: defaults)
        second.entitlements.entitlementState = .active(["app_access"])

        #expect(second.manager.takeOwedDeclineOffer() == false)
    }

    @Test
    func aClimberWhoPurchasedOnTheFirstPaywallIsNotOwedTheOffer() async {
        let defaults = makeDefaults()
        let launch = await makeLaunch(defaults: defaults)
        launch.coordinator.start()
        launch.presenter.send(.presented, registration: 0)
        launch.presenter.send(.purchased, registration: 0)

        #expect(DeclineOfferReplayStore(userDefaults: defaults).pendingUserID() == nil)
        let next = await makeLaunch(defaults: defaults)
        next.coordinator.start()
        #expect(next.presenter.placements == [.appAccessGate])
    }

    @Test
    func entitlementArrivingAtTheGateClearsTheMarker() async {
        let defaults = makeDefaults()
        let launch = await makeLaunch(defaults: defaults)
        launch.coordinator.start()
        launch.presenter.send(.presented, registration: 0)

        launch.coordinator.entitlementDidChange(.active(["app_access"]))

        #expect(DeclineOfferReplayStore(userDefaults: defaults).pendingUserID() == nil)
    }

    @Test
    func aClimberOnTheirFreeWeekIsNeverShownTheOffer() async {
        let defaults = makeDefaults()
        let first = await makeLaunch(defaults: defaults)
        first.coordinator.start()
        first.presenter.send(.presented, registration: 0)

        let second = await makeLaunch(defaults: defaults, runningWeekDaysAgo: 1)

        #expect(second.manager.hasAppAccess)
        #expect(second.manager.takeOwedDeclineOffer() == false)
    }

    @Test
    func startingTheFreeWeekClearsTheMarker() async {
        let defaults = makeDefaults()
        let launch = await makeLaunch(defaults: defaults)
        launch.freeWeek.granter.responses = [.success(.granted(launch.freeWeek.week()))]
        launch.coordinator.start()
        launch.presenter.send(.presented, registration: 0)
        // No campaign chained an offer, so the close goes straight to the letter and the week.
        launch.presenter.send(.dismissedWithoutPurchase, registration: 0)
        #expect(DeclineOfferReplayStore(userDefaults: defaults).pendingUserID() == "user-a")
        launch.presenter.send(.dismissedWithoutPurchase, registration: 1)

        #expect(await freeWeekWaitUntil { launch.coordinator.phase == .accessConfirmed })
        #expect(DeclineOfferReplayStore(userDefaults: defaults).pendingUserID() == nil)
    }

    @Test
    func anotherAccountSigningInDoesNotInheritTheOwedOffer() async {
        let defaults = makeDefaults()
        let first = await makeLaunch(defaults: defaults)
        first.coordinator.start()
        first.presenter.send(.presented, registration: 0)

        let second = await makeLaunch(defaults: defaults, userID: "user-b")
        second.coordinator.start()

        #expect(second.presenter.placements == [.appAccessGate])
    }

    @Test
    func signingOutClearsTheMarker() async {
        let defaults = makeDefaults()
        let launch = await makeLaunch(defaults: defaults)
        launch.coordinator.start()
        launch.presenter.send(.presented, registration: 0)

        launch.manager.clearPendingDeclineOffer()

        #expect(DeclineOfferReplayStore(userDefaults: defaults).pendingUserID() == nil)
    }

    // MARK: - Store

    @Test
    func theShownListIsBounded() {
        let store = DeclineOfferReplayStore(userDefaults: makeDefaults())

        for index in 0..<(DeclineOfferReplayStore.shownCapacity + 5) {
            store.markShown(for: "user-\(index)")
        }

        #expect(store.hasShown(for: "user-\(DeclineOfferReplayStore.shownCapacity + 4)"))
        #expect(store.hasShown(for: "user-0") == false)
    }

    // MARK: - Harness

    enum Switch: CaseIterable {
        case freeWeek
        case onboardingV3
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "DeclineOfferReplayTests-\(UUID().uuidString)")!
    }

    private func makeLaunch(
        defaults: UserDefaults,
        userID: String = "user-a",
        freeWeekEnabled: Bool = true,
        onboardingV3Enabled: Bool = true,
        walkedV3: Bool = true,
        runningWeekDaysAgo: Double? = nil
    ) async -> Launch {
        let identity = MonetizationIdentityTransition(revision: 1, userID: userID)
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = TelemetryManager(
            sinks: [sink],
            crashlyticsReporter: NoopCrashlyticsReporter(),
            collectionEnabledOverride: true,
            identityStore: makeTestIdentityStore()
        )
        telemetry.configure()
        telemetry.setUserId(userID)

        let freeWeek = FreeWeekTestHarness(isEnabled: freeWeekEnabled)
        if let runningWeekDaysAgo {
            freeWeek.cache.store(freeWeek.week(startingDaysAgo: runningWeekDaysAgo), for: userID)
        }
        freeWeek.store.setUser(userID)
        if freeWeekEnabled {
            _ = await freeWeekWaitUntil { freeWeek.store.record != .unknown }
        }

        let lifecycle = OnboardingFlowAnalyticsCoordinator(
            userDefaults: defaults,
            telemetry: telemetry
        )
        lifecycle.recordFlowStartedIfNeeded(
            context: OnboardingAnalyticsContext(
                segmentID: "pre_auth_welcome",
                flowVersion: walkedV3
                    ? OnboardingAnalyticsContext.currentFlowVersion
                    : OnboardingAnalyticsContext.legacyFlowVersion,
                stepID: "welcome"
            )
        )

        let presenter = GateTestPresenter()
        let entitlements = GateTestEntitlementService(identity: identity)
        let clock = GateTestClock()
        let manager = MonetizationManager(
            configuration: makeGateTestConfiguration(),
            entitlementService: entitlements,
            paywallPresenter: presenter,
            appAccessReconciler: GateTestReconciler(),
            freeWeek: freeWeek.store,
            telemetry: telemetry,
            onboardingLifecycle: lifecycle,
            userDefaults: defaults,
            isOnboardingV3Enabled: { onboardingV3Enabled }
        )
        let coordinator = AppAccessPaywallCoordinator(
            monetizationManager: manager,
            telemetry: telemetry,
            retryPolicy: .test,
            sleep: clock.sleep
        )
        return Launch(
            coordinator: coordinator,
            manager: manager,
            presenter: presenter,
            entitlements: entitlements,
            freeWeek: freeWeek
        )
    }

    struct Launch {
        let coordinator: AppAccessPaywallCoordinator
        let manager: MonetizationManager
        let presenter: GateTestPresenter
        let entitlements: GateTestEntitlementService
        let freeWeek: FreeWeekTestHarness
    }
}
