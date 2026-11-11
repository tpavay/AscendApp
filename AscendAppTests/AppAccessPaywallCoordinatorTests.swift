import Foundation
import Testing
@testable import AscendApp

/// What the app-access gate does with every answer Superwall, Apple and the server can give it.
///
/// The gate draws a spinner and nothing else, so no answer may end somewhere that needs words or a
/// control. Each test here ends in one of the only three places there are: the app, a hosted
/// screen, or the spinner while the gate asks again on a clock.
@MainActor
@Suite(.serialized)
struct AppAccessPaywallCoordinatorTests {
    // MARK: - Opening the paywall

    @Test
    func startingAsksSuperwallForTheAccessPaywallAndWaitsBehindIt() async {
        let harness = makeHarness()

        harness.coordinator.start()
        #expect(harness.presenter.placements == [.appAccessGate])
        #expect(harness.presenter.sources == ["app_access_gate"])
        #expect(harness.coordinator.phase == .openingHosted)

        harness.presenter.send(.presented, registration: 0)
        await gateSettle()

        #expect(harness.coordinator.phase == .hostedPresented)
        #expect(harness.presenter.cancelCount == 0)
        // The opening deadline was stood down, and nothing else was put on a clock.
        #expect(harness.clock.pending.isEmpty)
    }

    @Test
    func startingTwiceAsksOnce() {
        let harness = makeHarness()

        harness.coordinator.start()
        harness.coordinator.start()

        #expect(harness.presenter.placements == [.appAccessGate])
    }

    // MARK: - A paywall Superwall cannot present

    @Test
    func aPaywallThatNeverOpensIsCancelledAndAskedForAgainAfterTheBackoff() async {
        let harness = makeHarness()

        harness.coordinator.start()
        await harness.clock.fire(gateOpeningDeadline)
        #expect(await gateWaitUntil { harness.coordinator.phase == .awaitingHostedRetry })

        #expect(harness.presenter.cancelCount == 1)
        #expect(harness.presenter.placements == [.appAccessGate])
        let terminals = harness.terminals
        #expect(terminals.count == 1)
        #expect(terminals[0].parameters["provider_outcome"] == .string("hosted_unavailable"))
        #expect(terminals[0].parameters["recovery_path"] == .string("hosted"))
        #expect(terminals[0].parameters["recovery_reason"] == .string("watchdog_timeout"))
        #expect(terminals[0].parameters["identity_match"] == .bool(true))
        #expect(terminals[0].parameters["entitlement_active"] == .bool(false))
        if case .string(let attemptID) = terminals[0].parameters["gate_attempt_id"] {
            #expect(UUID(uuidString: attemptID) != nil)
        } else {
            Issue.record("Gate terminal must carry a bounded attempt correlation ID")
        }
        #expect(terminals[0].parameters["storekit_receipt_name"] != nil)

        await harness.clock.fire(.seconds(101))
        #expect(await gateWaitUntil { harness.presenter.placements.count == 2 })

        #expect(harness.presenter.placements == [.appAccessGate, .appAccessGate])
        #expect(harness.presenter.sources.last == "presentation_retry")
        #expect(harness.coordinator.phase == .openingHosted)
    }

    @Test(arguments: [
        (PaywallPresentationOutcome.skipped(reason: "rule"), "hosted_skipped"),
        (PaywallPresentationOutcome.failed(message: "provider"), "hosted_error")
    ])
    func aPaywallSuperwallRefusesIsAskedForAgainAfterTheBackoff(
        outcome: PaywallPresentationOutcome,
        reason: String
    ) async {
        let harness = makeHarness()
        harness.coordinator.start()

        harness.presenter.send(outcome, registration: 0)

        #expect(harness.coordinator.phase == .awaitingHostedRetry)
        #expect(harness.presenter.placements == [.appAccessGate])
        #expect(harness.terminals.map { $0.parameters["provider_outcome"] } == [.string("hosted_unavailable")])
        #expect(harness.terminals.first?.parameters["recovery_reason"] == .string(reason))

        await harness.clock.fire(.seconds(101))
        #expect(await gateWaitUntil { harness.presenter.placements.count == 2 })
        #expect(harness.coordinator.phase == .openingHosted)
    }

    @Test
    func theWaitGrowsWithEveryFailureAndThenHoldsAtItsCeilingForAsLongAsTheGateIsUp() async {
        let harness = makeHarness()
        harness.coordinator.start()

        for (attempt, wait) in [101, 102, 103, 103, 103].enumerated() {
            harness.presenter.send(.skipped(reason: "rule"), registration: attempt)
            #expect(harness.coordinator.phase == .awaitingHostedRetry)
            await harness.clock.fire(.seconds(wait))
            #expect(await gateWaitUntil { harness.presenter.placements.count == attempt + 2 })
        }

        // Six asks, and the gate is still asking: there is nothing to fall back to.
        #expect(harness.presenter.placements.count == 6)
        #expect(harness.coordinator.phase == .openingHosted)
        #expect(
            harness.clock.requested.filter { $0 != gateOpeningDeadline }
                == [101, 102, 103, 103, 103].map { Duration.seconds($0) }
        )
    }

    @Test
    func aPaywallThatOpensResetsTheBackoff() async {
        let harness = makeHarness()
        harness.coordinator.start()
        harness.presenter.send(.skipped(reason: "rule"), registration: 0)
        await harness.clock.fire(.seconds(101))
        #expect(await gateWaitUntil { harness.presenter.placements.count == 2 })
        harness.presenter.send(.skipped(reason: "rule"), registration: 1)
        await harness.clock.fire(.seconds(102))
        #expect(await gateWaitUntil { harness.presenter.placements.count == 3 })

        harness.presenter.send(.presented, registration: 2)
        // The climber closes it, and with no free week on offer it reopens at once.
        harness.presenter.send(.dismissedWithoutPurchase, registration: 2)
        #expect(harness.presenter.placements.count == 4)
        harness.presenter.send(.skipped(reason: "rule"), registration: 3)

        #expect(harness.coordinator.phase == .awaitingHostedRetry)
        #expect(await harness.clock.waitUntilPending(.seconds(101)))
        #expect(!harness.clock.pending.contains(.seconds(103)))
    }

    @Test
    func comingBackToTheAppAsksAgainAtOnceAndRestartsTheBackoff() async {
        let harness = makeHarness()
        harness.coordinator.start()
        harness.presenter.send(.skipped(reason: "rule"), registration: 0)
        await harness.clock.fire(.seconds(101))
        #expect(await gateWaitUntil { harness.presenter.placements.count == 2 })
        harness.presenter.send(.skipped(reason: "rule"), registration: 1)
        #expect(await harness.clock.waitUntilPending(.seconds(102)))

        harness.coordinator.appWillEnterForeground()

        #expect(harness.presenter.placements.count == 3)
        #expect(harness.presenter.sources.last == "foreground_retry")
        #expect(harness.coordinator.phase == .openingHosted)
        // The wait that was running is gone rather than left to ask a second time.
        #expect(await gateWaitUntil { !harness.clock.pending.contains(.seconds(102)) })

        harness.presenter.send(.skipped(reason: "rule"), registration: 2)
        #expect(await harness.clock.waitUntilPending(.seconds(101)))
    }

    @Test(arguments: [false, true])
    func comingBackToTheAppLeavesAPaywallThatIsOpeningOrOpenAlone(isPresented: Bool) async {
        let harness = makeHarness()
        harness.coordinator.start()
        if isPresented {
            harness.presenter.send(.presented, registration: 0)
        }

        harness.coordinator.appWillEnterForeground()
        await gateSettle()

        #expect(harness.presenter.placements == [.appAccessGate])
        #expect(harness.presenter.cancelCount == 0)
        #expect(harness.coordinator.phase == (isPresented ? .hostedPresented : .openingHosted))
    }

    @Test
    func aLateCallbackFromAPaywallThatFailedCannotMoveTheGate() async {
        let harness = makeHarness()
        harness.coordinator.start()
        await harness.clock.fire(gateOpeningDeadline)
        #expect(await gateWaitUntil { harness.coordinator.phase == .awaitingHostedRetry })

        harness.presenter.send(.presented, registration: 0)
        harness.presenter.send(.dismissedWithoutPurchase, registration: 0)
        await gateSettle()

        #expect(harness.coordinator.phase == .awaitingHostedRetry)
        #expect(harness.presenter.placements == [.appAccessGate])
        #expect(harness.terminals.count == 1)
    }

    @Test
    func leavingTheGateStopsItAskingAgain() async {
        let harness = makeHarness()
        harness.coordinator.start()
        harness.presenter.send(.skipped(reason: "rule"), registration: 0)
        #expect(await harness.clock.waitUntilPending(.seconds(101)))

        harness.coordinator.cancelOwnedWork()

        #expect(await gateWaitUntil { harness.clock.pending.isEmpty })
        await gateSettle()
        #expect(harness.presenter.placements == [.appAccessGate])
    }

    @Test
    func anAccountCheckThatHasNotFinishedWaitsBehindTheSpinnerAndOpensThePaywallWhenItLands() async {
        let harness = makeHarness(identity: nil)

        harness.coordinator.start()
        #expect(harness.presenter.placements.isEmpty)
        #expect(harness.coordinator.phase == .awaitingHostedRetry)

        // Still no account when the wait ends, so the gate waits again rather than giving up.
        await harness.clock.fire(.seconds(101))
        #expect(await harness.clock.waitUntilPending(.seconds(102)))
        #expect(harness.presenter.placements.isEmpty)

        harness.entitlements.identityGeneration = MonetizationIdentityTransition(
            revision: 1,
            userID: "user-a"
        )
        harness.coordinator.identityDidChange()

        #expect(harness.presenter.placements == [.appAccessGate])
        #expect(harness.coordinator.phase == .openingHosted)
        #expect(await gateWaitUntil { !harness.clock.pending.contains(.seconds(102)) })
    }

    // MARK: - A purchase that has not turned into access

    @Test
    func anUnconfirmedChargeIsCheckedOnTheScheduleBehindTheSpinnerThenThePaywallReopens() async {
        let harness = makeHarness()
        harness.coordinator.start()
        harness.presenter.send(.presented, registration: 0)
        harness.manager.holdPendingPurchase(.unconfirmedCharge)

        harness.presenter.send(.verificationUnavailable, registration: 0)

        #expect(harness.coordinator.phase == .confirmingAccess)
        #expect(await gateWaitUntil { harness.entitlements.refreshCount == 1 })
        await harness.clock.fire(.seconds(301))
        #expect(await gateWaitUntil { harness.entitlements.refreshCount == 2 })
        #expect(harness.coordinator.phase == .confirmingAccess)
        #expect(harness.presenter.placements == [.appAccessGate])
        await harness.clock.fire(.seconds(302))

        #expect(await gateWaitUntil { harness.presenter.placements.count == 2 })
        #expect(harness.entitlements.refreshCount == 3)
        #expect(harness.presenter.sources.last == "access_unconfirmed")
        #expect(harness.coordinator.phase == .openingHosted)
        // Released, or the paywall could never reopen and the climber could never reach restore,
        // sign out or account deletion.
        #expect(harness.manager.pendingPurchaseHold == nil)
        #expect(
            harness.terminals.map { $0.parameters["provider_outcome"] }
                == [.string("verification_unavailable")]
        )
    }

    @Test
    func anUnconfirmedChargeThatConfirmsOnALaterCheckOpensTheApp() async {
        let harness = makeHarness()
        harness.entitlements.stateAfterRefresh = [2: .active(["app_access"])]
        harness.coordinator.start()
        harness.presenter.send(.presented, registration: 0)

        harness.presenter.send(.verificationUnavailable, registration: 0)
        #expect(await gateWaitUntil { harness.entitlements.refreshCount == 1 })
        #expect(harness.coordinator.phase == .confirmingAccess)
        await harness.clock.fire(.seconds(301))

        #expect(await gateWaitUntil { harness.coordinator.phase == .accessConfirmed })
        await gateSettle()
        #expect(harness.presenter.placements == [.appAccessGate])
        // Nothing is left running but the wait for routing to leave the gate.
        #expect(harness.clock.pending == [gateRouteDeadline])
    }

    @Test
    func anAskToBuyIsCheckedOnceAndThenThePaywallComesBack() async {
        let harness = makeHarness()
        harness.coordinator.start()
        harness.presenter.send(.presented, registration: 0)
        harness.manager.holdPendingPurchase(.askToBuy)

        harness.presenter.send(.pendingApproval, registration: 0)
        #expect(harness.coordinator.phase == .confirmingAccess)

        #expect(await gateWaitUntil { harness.presenter.placements.count == 2 })
        #expect(harness.entitlements.refreshCount == 1)
        #expect(harness.presenter.sources.last == "ask_to_buy_pending")
        #expect(harness.manager.pendingPurchaseHold == nil)
        // Approval is a person's decision; no clock is spent waiting on it.
        #expect(!harness.clock.requested.contains(.seconds(301)))
    }

    @Test
    func aChargeLeftUnconfirmedByTheLastLaunchIsCheckedBeforeAnythingIsOffered() async {
        let harness = makeHarness()
        harness.manager.holdPendingPurchase(.unconfirmedCharge)

        harness.coordinator.start()

        #expect(harness.presenter.placements.isEmpty)
        #expect(harness.coordinator.phase == .confirmingAccess)
        #expect(await gateWaitUntil { harness.entitlements.refreshCount == 1 })
        await harness.clock.fire(.seconds(301))
        await harness.clock.fire(.seconds(302))

        #expect(await gateWaitUntil { harness.presenter.placements == [.appAccessGate] })
        #expect(harness.manager.pendingPurchaseHold == nil)
    }

    @Test
    func accessLandingWhileAChargeIsBeingCheckedOpensTheAppAndNothingReopens() async {
        let harness = makeHarness()
        harness.coordinator.start()
        harness.presenter.send(.presented, registration: 0)
        harness.presenter.send(.verificationUnavailable, registration: 0)
        #expect(await harness.clock.waitUntilPending(.seconds(301)))

        harness.coordinator.entitlementDidChange(.active(["app_access"]))

        #expect(harness.coordinator.phase == .accessConfirmed)
        #expect(await gateWaitUntil { harness.clock.pending == [gateRouteDeadline] })
        await gateSettle()
        #expect(harness.presenter.placements == [.appAccessGate])
    }

    // MARK: - Access

    @Test(arguments: [
        (PaywallPresentationOutcome.purchased, "purchased"),
        (PaywallPresentationOutcome.restored, "restored")
    ])
    func aPurchaseOrRestoreFromTheHostedPaywallWaitsBehindTheSpinnerForTheRoute(
        outcome: PaywallPresentationOutcome,
        providerOutcome: String
    ) async {
        let harness = makeHarness()
        harness.coordinator.start()
        harness.presenter.send(.presented, registration: 0)

        harness.presenter.send(outcome, registration: 0)
        await gateSettle()

        #expect(harness.coordinator.phase == .accessConfirmed)
        #expect(harness.presenter.placements == [.appAccessGate])
        #expect(harness.clock.pending == [gateRouteDeadline])
        #expect(harness.terminals.map { $0.parameters["provider_outcome"] } == [.string(providerOutcome)])
        #expect(harness.terminals.first?.parameters["entitlement_active"] == .bool(true))
    }

    /// Routing reads what the gate reads, so it leaves in the same turn. If it ever does not, the
    /// spinner must not be where the climber is left.
    @Test
    func aConfirmationRoutingNeverActsOnReopensThePaywallRatherThanLeavingASpinner() async {
        let harness = makeHarness()
        harness.coordinator.start()
        harness.presenter.send(.presented, registration: 0)
        harness.presenter.send(.purchased, registration: 0)
        #expect(harness.coordinator.phase == .accessConfirmed)

        await harness.clock.fire(gateRouteDeadline)

        #expect(await gateWaitUntil { harness.presenter.placements.count == 2 })
        #expect(harness.presenter.sources.last == "access_route_unresolved")
        #expect(harness.coordinator.phase == .openingHosted)
    }

    /// A gate that left the screen and is shown again starts over, instead of sitting on a spinner
    /// that nothing is driving.
    @Test
    func aGateThatLeftTheScreenStartsOverWhenItIsShownAgain() async {
        let harness = makeHarness()
        harness.coordinator.start()
        harness.presenter.send(.presented, registration: 0)

        harness.coordinator.cancelOwnedWork()
        #expect(harness.coordinator.phase == .openingHosted)
        harness.coordinator.start()

        #expect(harness.presenter.placements == [.appAccessGate, .appAccessGate])
        #expect(harness.presenter.sources.last == "app_access_gate")
    }

    @Test
    func activeEntitlementRetiresTheRetryAndEveryLateHostedCallback() async {
        let harness = makeHarness()
        harness.coordinator.start()
        harness.presenter.send(.skipped(reason: "test"), registration: 0)
        #expect(await harness.clock.waitUntilPending(.seconds(101)))

        harness.coordinator.entitlementDidChange(.active(["app_access"]))
        harness.presenter.send(.dismissedWithoutPurchase, registration: 0)
        await gateSettle()

        #expect(harness.coordinator.phase == .accessConfirmed)
        #expect(await gateWaitUntil { harness.clock.pending == [gateRouteDeadline] })
        #expect(harness.presenter.placements == [.appAccessGate])
    }

    // MARK: - Identity

    @Test
    func identityChangeRecordsOneRedactedStaleTerminalAndIgnoresOldCallback() async {
        let harness = makeHarness()
        harness.coordinator.start()

        harness.entitlements.identityGeneration = MonetizationIdentityTransition(
            revision: 2,
            userID: "user-b"
        )
        harness.coordinator.identityDidChange()
        harness.presenter.send(.failed(message: "raw provider detail"), registration: 0)
        await gateSettle()

        #expect(harness.presenter.placements == [.appAccessGate, .appAccessGate])
        #expect(harness.coordinator.phase == .openingHosted)
        let terminals = harness.terminals
        #expect(terminals.count == 1)
        #expect(terminals[0].parameters["provider_outcome"] == .string("stale_identity"))
        #expect(terminals[0].parameters["identity_match"] == .bool(false))
        #expect(terminals[0].parameters.values.contains(.string("user-a")) == false)
        #expect(terminals[0].parameters.values.contains(.string("user-b")) == false)
        #expect(terminals[0].parameters.values.contains(.string("raw provider detail")) == false)
    }

    @Test
    func anAccessCheckStillRunningCannotAnswerForANewIdentity() async {
        let harness = makeHarness()
        harness.coordinator.start()
        harness.presenter.send(.presented, registration: 0)
        harness.presenter.send(.verificationUnavailable, registration: 0)
        #expect(await harness.clock.waitUntilPending(.seconds(301)))

        harness.entitlements.identityGeneration = MonetizationIdentityTransition(
            revision: 2,
            userID: "user-b"
        )
        harness.coordinator.identityDidChange()
        await gateSettle()

        #expect(harness.coordinator.phase == .openingHosted)
        #expect(harness.presenter.placements == [.appAccessGate, .appAccessGate])
        #expect(!harness.clock.pending.contains(.seconds(301)))
    }

    @Test
    func switchingTelemetryIdentityFirstSuppressesTheOldGateTerminalAndAttributesTheNewAttempt() async {
        let attributionSink = IdentityAttributingTelemetrySink()
        let harness = makeHarness(attributionSink: attributionSink)
        harness.coordinator.start()

        harness.telemetry.setUserId("user-b")
        harness.entitlements.identityGeneration = MonetizationIdentityTransition(
            revision: 2,
            userID: "user-b"
        )
        harness.coordinator.identityDidChange()
        harness.presenter.send(.skipped(reason: "new-account"), registration: 1)
        #expect(harness.coordinator.phase == .awaitingHostedRetry)

        let terminals = attributionSink.attributions.filter {
            $0.name == "app_access_gate_attempt_terminal"
        }
        let reached = attributionSink.attributions.filter {
            $0.name == "paywall_reached"
        }
        #expect(reached.map(\.userID) == ["user-a", "user-b"])
        #expect(terminals.count == 1)
        #expect(terminals.first?.userID == "user-b")
        #expect(terminals.first?.parameters["provider_outcome"] == .string("hosted_unavailable"))
        #expect(terminals.first?.parameters["identity_match"] == .bool(true))
        #expect(terminals.first?.parameters["user_id"] == nil)
        #expect(terminals.first?.parameters["identity_revision"] == nil)
    }

    // MARK: - Diagnostics and the shipped schedule

    @Test
    func rawPaywallLifecycleRecordsCarryStoreKitDiagnosticsWithoutRawErrors() {
        let diagnostics = StoreKitEnvironmentDiagnostics(
            receiptName: { "sandboxReceipt" },
            telemetry: makeTestTelemetry(
                sink: InMemoryTelemetrySink(destination: .analytics)
            )
        )

        for name in ["paywall_reached", "paywall_skipped", "paywall_error"] {
            let record = PaywallAnalyticsEvent.diagnosticRecord(
                name: name,
                parameters: ["placement": .string("app_access_gate")],
                diagnostics: diagnostics
            )
            #expect(record.parameters["storekit_receipt_name"] == .string("sandboxReceipt"))
            #expect(record.parameters["error"] == nil)
        }
    }

    @Test
    func theShippedScheduleBacksOffToAMinuteAndBoundsEveryOtherWait() {
        let policy = AppAccessGateRetryPolicy()

        #expect(policy.hostedPresentationDelays == [2, 4, 8, 16, 32, 60].map { Duration.seconds($0) })
        #expect(policy.hostedPresentationDelay(afterFailures: 0) == .seconds(2))
        #expect(policy.hostedPresentationDelay(afterFailures: 5) == .seconds(60))
        // The ceiling repeats: the gate never stops asking for its only way through.
        #expect(policy.hostedPresentationDelay(afterFailures: 6) == .seconds(60))
        #expect(policy.hostedPresentationDelay(afterFailures: 600) == .seconds(60))
        #expect(policy.freeWeekDelays == [2, 4, 8].map { Duration.seconds($0) })
        #expect(policy.accessCheckDelays == [2, 4, 8, 16].map { Duration.seconds($0) })
        #expect(policy.routeResolutionDeadline == .seconds(10))
        // A wait of nothing would turn a failing paywall into a spin.
        #expect((policy.hostedPresentationDelays + policy.freeWeekDelays + policy.accessCheckDelays)
            .allSatisfy { $0 >= .seconds(1) })
    }

    /// Every phase is a wait behind the same spinner, so none of them may be a place the gate
    /// stops and shows something of its own.
    @Test
    func noPhaseIsANativeScreen() {
        #expect(AppAccessGatePhase.allCases == [
            .openingHosted,
            .hostedPresented,
            .awaitingHostedRetry,
            .confirmingAccess,
            .accessConfirmed,
            .openingLetter,
            .letterPresented,
            .startingFreeWeek
        ])
    }

    // MARK: - Harness

    private func makeHarness(
        identity: MonetizationIdentityTransition? = MonetizationIdentityTransition(
            revision: 1,
            userID: "user-a"
        ),
        attributionSink: IdentityAttributingTelemetrySink? = nil
    ) -> CoordinatorHarness {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        var sinks: [any TelemetrySink] = [sink]
        if let attributionSink {
            sinks.append(attributionSink)
        }
        let telemetry = TelemetryManager(
            sinks: sinks,
            crashlyticsReporter: NoopCrashlyticsReporter(),
            collectionEnabledOverride: true,
            identityStore: makeTestIdentityStore()
        )
        telemetry.configure()
        telemetry.setUserId(identity?.userID ?? "user-a")
        let entitlements = GateTestEntitlementService(identity: identity)
        let presenter = GateTestPresenter()
        let clock = GateTestClock()
        let manager = MonetizationManager(
            configuration: makeGateTestConfiguration(),
            entitlementService: entitlements,
            paywallPresenter: presenter,
            appAccessReconciler: GateTestReconciler(),
            // The free week has its own suite; here a decline is the hard paywall reopening.
            freeWeek: FreeWeekTestHarness(isEnabled: false).store,
            telemetry: telemetry,
            userDefaults: UserDefaults(
                suiteName: "AppAccessPaywallCoordinatorTests-\(UUID().uuidString)"
            )!
        )
        let coordinator = AppAccessPaywallCoordinator(
            monetizationManager: manager,
            telemetry: telemetry,
            retryPolicy: .test,
            sleep: clock.sleep
        )
        return CoordinatorHarness(
            coordinator: coordinator,
            manager: manager,
            entitlements: entitlements,
            presenter: presenter,
            clock: clock,
            sink: sink,
            telemetry: telemetry
        )
    }
}

@MainActor
private struct CoordinatorHarness {
    let coordinator: AppAccessPaywallCoordinator
    let manager: MonetizationManager
    let entitlements: GateTestEntitlementService
    let presenter: GateTestPresenter
    let clock: GateTestClock
    let sink: InMemoryTelemetrySink
    let telemetry: TelemetryManager

    var terminals: [EnvelopedTelemetryRecord] {
        sink.records.filter { $0.name == "app_access_gate_attempt_terminal" }
    }
}
