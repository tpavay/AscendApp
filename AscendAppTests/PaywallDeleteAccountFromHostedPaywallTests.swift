import Foundation
import enum SuperwallKit.PurchaseResult
import Testing
@testable import AscendApp

/// With no close control on the hosted paywall, `DELETE ACCOUNT` is the route Guideline 5.1.1(v)
/// requires for a locked-out climber who cannot pay. It shipped as a custom action the app did not
/// model, so the control did nothing at all - not even dismiss the paywall.
///
/// Ascend owns that dismissal rather than letting the editor chain a close after the action,
/// because nothing the app presents can appear over a live paywall: Superwall holds its own
/// `UIWindow` above the app's (`docs/superwall-paywall-setup.md`). So the deletion dialog can only
/// be raised once the paywall is gone, and the app is what takes it away.
struct PaywallDeleteAccountFromHostedPaywallTests {
    /// The whole defect was a name the app had no case for, and an unmodelled name is
    /// indistinguishable from an ordinary close. The recognised set is therefore derived from
    /// `SuperwallCustomAction` itself rather than restated here: a case added to production
    /// without a resolved intent fails this test instead of failing silently in a climber's hands.
    @Test
    func everyModelledActionResolvesAndNothingElseDoes() {
        #expect(SuperwallCustomAction.allCases.map(\.rawValue).sorted() == ["back", "delete_account"])

        for action in SuperwallCustomAction.allCases {
            let intent = PaywallDismissIntent.resolve(latchedActionName: action.rawValue)
            #expect(
                intent == PaywallDismissIntent.resolve(action),
                "\(action.rawValue) must resolve the same way by name as by case"
            )
            #expect(
                intent != .undifferentiated,
                "\(action.rawValue) is modelled, so it must not degrade to an ordinary dismissal"
            )
        }

        // Every other name - a control the editor adds before the app models it, a typo, a
        // near-miss on a recognised name - degrades to an ordinary dismissal and never borrows
        // another control's behaviour.
        let modelled = Set(SuperwallCustomAction.allCases.map(\.rawValue))
        for unmodelled in [
            "", "Back", "DELETE_ACCOUNT", "delete-account", "deleteAccount", "delete_account ",
            "close", "manage_subscription", "restore", "sign_out", "terms"
        ] {
            #expect(!modelled.contains(unmodelled))
            #expect(
                PaywallDismissIntent.resolve(latchedActionName: unmodelled) == .undifferentiated,
                "\(unmodelled) must not be mistaken for a modelled control"
            )
        }
        #expect(PaywallDismissIntent.resolve(latchedActionName: nil) == .undifferentiated)

        #expect(PaywallDismissIntent.deleteAccount.outcome == .deleteAccountRequested)
        #expect(PaywallPresentationOutcome.deleteAccountRequested.isTerminal)
    }

    /// The two arrangements are mutually exclusive, and getting one backwards is what breaks a
    /// control. Pinned as a property of the enum so a third control has to state which it is.
    @Test
    func eachControlDeclaresExactlyOneDismissalOwner() {
        #expect(SuperwallCustomAction.back.isDismissedByAscend == false)
        #expect(SuperwallCustomAction.deleteAccount.isDismissedByAscend)
    }

    /// The exact defect: the control fires its custom action and chains nothing, so if the app does
    /// not answer on arrival, nothing happens at all.
    @MainActor
    @Test
    func aDeleteAccountActionAloneReportsTheOutcomeAndDismissesThePaywall() async {
        let dismissals = DismissalSpy()
        let presenter = SuperwallPaywallPresenter(
            startsConfigured: true,
            dismissPresentation: { await dismissals.record() }
        )
        var outcomes: [PaywallPresentationOutcome] = []
        let identity = MonetizationIdentityTransition(revision: 1, userID: "user-1")
        let revision = presenter.beginPresentationAttemptForTesting(identity: identity) {
            outcomes.append($0)
        }
        presenter.handlePresentationBegan(revision: revision, presentationID: "presentation-1")

        presenter.handleCustomPaywallAction(withName: "delete_account")

        // Superwall's window sits above the app's, so nothing Ascend raises in answer to this
        // action is visible until the paywall is gone: the outcome is reported after the dismissal
        // it owns, never before it.
        #expect(outcomes.isEmpty, "the outcome must not be reported while the paywall is still up")
        await presenter.drainPresentationOperationsForTesting()
        #expect(outcomes == [.deleteAccountRequested])
        #expect(await dismissals.count == 1)
    }

    /// Ascend caused that dismissal, so the close it produces must not be reported a second time -
    /// a second `.deleteAccountRequested` would open the deletion dialog twice.
    @MainActor
    @Test
    func theDismissalAscendCausedIsNotReportedAgain() async {
        let dismissals = DismissalSpy()
        let presenter = SuperwallPaywallPresenter(
            startsConfigured: true,
            dismissPresentation: { await dismissals.record() }
        )
        var outcomes: [PaywallPresentationOutcome] = []
        let identity = MonetizationIdentityTransition(revision: 1, userID: "user-1")
        let revision = presenter.beginPresentationAttemptForTesting(identity: identity) {
            outcomes.append($0)
        }
        presenter.handlePresentationBegan(revision: revision, presentationID: "presentation-1")

        presenter.handleCustomPaywallAction(withName: "delete_account")
        // A double tap while the dismissal is in flight, then the close itself.
        presenter.handleCustomPaywallAction(withName: "delete_account")
        presenter.handleDismissForTesting(revision: revision, result: .declined)

        await presenter.drainPresentationOperationsForTesting()
        #expect(outcomes == [.deleteAccountRequested])
        #expect(await dismissals.count == 1, "the second tap must not dismiss a second time")
    }

    /// Back is the other arrangement and must keep working unchanged: it waits for the close its
    /// paywall chains, and reports nothing on arrival.
    @MainActor
    @Test
    func aLatchedControlStillWaitsForTheCloseItsPaywallChains() {
        let presenter = SuperwallPaywallPresenter(startsConfigured: true)
        var outcomes: [PaywallPresentationOutcome] = []
        let identity = MonetizationIdentityTransition(revision: 1, userID: "user-1")
        let revision = presenter.beginPresentationAttemptForTesting(identity: identity) {
            outcomes.append($0)
        }
        presenter.handlePresentationBegan(revision: revision, presentationID: "presentation-1")

        presenter.handleCustomPaywallAction(withName: "back")
        #expect(outcomes.isEmpty)

        presenter.handleDismissForTesting(revision: revision, result: .declined)
        #expect(outcomes == [.backRequested])
    }

    @MainActor
    @Test
    func deleteAccountOpensTheAccountDeletionDialogWithoutLoadingTheNativePlanList() {
        let harness = GateDeleteAccountHarness()

        harness.openHostedPaywall()
        harness.coordinator.handleHostedOutcomeForTesting(.deleteAccountRequested)

        #expect(harness.deletionRequestCount == 1)
        #expect(harness.nativeProvider.loadCount == 0)
        // The phase deliberately does not move: a change here would announce "Loading subscription
        // options." over the deletion dialog to a VoiceOver climber.
        #expect(harness.coordinator.phase == .hostedPresented)

        let terminals = harness.gateTerminals
        #expect(terminals.count == 1)
        #expect(terminals[0].parameters["provider_outcome"] == .string("delete_account_requested"))
        #expect(terminals[0].parameters["recovery_path"] == .string("account"))
        #expect(
            terminals[0].parameters["recovery_reason"] == .string("hosted_delete_account_requested")
        )
    }

    /// Ascend dismissed the paywall to raise the dialog, so backing out of the deletion has to put
    /// the climber back on it. Cancelling a deletion means nothing happened - not a plan list, and
    /// not an opening spinner with no controls at all.
    @MainActor
    @Test
    func cancellingTheDeletionBringsTheHostedPaywallBack() {
        let harness = GateDeleteAccountHarness()

        harness.openHostedPaywall()
        #expect(harness.presenter.registrationCount == 1)
        harness.coordinator.handleHostedOutcomeForTesting(.deleteAccountRequested)

        harness.coordinator.accountDeletionDialogDismissed()

        #expect(harness.presenter.registrationCount == 2)
        #expect(harness.coordinator.phase == .openingHosted)
        #expect(harness.nativeProvider.loadCount == 0)
    }

    /// Cancelling brings the paywall back, so the gate says so rather than restoring focus to a
    /// `Delete account` control that is about to stop being rendered.
    @MainActor
    @Test
    func theGateReportsWhetherCancellingReopensTheHostedPaywall() {
        let harness = GateDeleteAccountHarness()

        harness.openHostedPaywall()
        harness.coordinator.handleHostedOutcomeForTesting(.deleteAccountRequested)
        #expect(harness.coordinator.accountDeletionDialogDismissed())

        // From the native recovery surface there is no paywall to bring back, so the gate keeps
        // focus on the control the climber actually left from.
        harness.coordinator.handleHostedOutcomeForTesting(.dismissedWithoutPurchase)
        #expect(harness.coordinator.accountDeletionDialogDismissed() == false)
    }

    /// A deletion raised from the gate's own control leaves the native recovery surface alone.
    @MainActor
    @Test
    func aDismissedDeletionDoesNotReopenThePaywallFromANativePhase() async {
        let harness = GateDeleteAccountHarness()

        harness.openHostedPaywall()
        harness.coordinator.handleHostedOutcomeForTesting(.dismissedWithoutPurchase)
        await harness.waitUntil { $0.phase == .nativeReady }
        let registrationsBefore = harness.presenter.registrationCount

        harness.coordinator.accountDeletionDialogDismissed()

        #expect(harness.presenter.registrationCount == registrationsBefore)
        #expect(harness.coordinator.phase == .nativeReady)
    }
}

private actor DismissalSpy {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

@MainActor
private final class GateDeleteAccountHarness {
    let coordinator: AppAccessPaywallCoordinator
    let nativeProvider = DeleteAccountNativeProviderSpy()
    let presenter = RegisteringPaywallPresenterSpy()
    private let sink = InMemoryTelemetrySink(destination: .analytics)
    private let deletionSpy = AccountDeletionRequestSpy()

    var deletionRequestCount: Int { deletionSpy.count }

    var gateTerminals: [EnvelopedTelemetryRecord] {
        sink.records.filter { $0.name == "app_access_gate_attempt_terminal" }
    }

    init() {
        let telemetry = makeTestTelemetry(sink: sink)
        telemetry.setUserId("test-user")
        let manager = MonetizationManager(
            configuration: MonetizationConfiguration(infoDictionary: [
                MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "NO"
            ]),
            entitlementService: EntitlementServiceStub(entitlementState: .inactive),
            paywallPresenter: presenter,
            telemetry: telemetry,
            onboardingLifecycle: makeScratchOnboardingLifecycle(telemetry: telemetry),
            userDefaults: UserDefaults(
                suiteName: "PaywallDeleteAccountFromHostedPaywallTests.\(UUID().uuidString)"
            )!
        )
        let deletion = deletionSpy
        coordinator = AppAccessPaywallCoordinator(
            monetizationManager: manager,
            nativeProvider: nativeProvider,
            telemetry: telemetry,
            onRequestAccountDeletion: { deletion.request() },
            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) },
            nativeLoadSleep: { _ in try await Task.sleep(for: .seconds(3_600)) }
        )
    }

    func openHostedPaywall() {
        coordinator.start()
        coordinator.handleHostedOutcomeForTesting(.presented)
        #expect(coordinator.phase == .hostedPresented)
    }

    func waitUntil(_ condition: (AppAccessPaywallCoordinator) -> Bool) async {
        for _ in 0..<200 where !condition(coordinator) {
            await Task.yield()
        }
    }
}

@MainActor
private final class AccountDeletionRequestSpy {
    private(set) var count = 0

    func request() {
        count += 1
    }
}

@MainActor
private final class RegisteringPaywallPresenterSpy: PaywallPresenting {
    let isConfigured = true
    private(set) var registrationCount = 0

    func configure(configuration: MonetizationConfiguration) {}
    func identify(userId: String) {}
    func resetIdentity() {}
    func cancelPresentation() {}

    func register(
        placement: SuperwallPlacement,
        params: [String: Any]?,
        onOutcome: @escaping @MainActor (PaywallPresentationOutcome) -> Void
    ) {
        registrationCount += 1
    }
}

@MainActor
private final class DeleteAccountNativeProviderSpy: NativeSubscriptionProviding {
    private(set) var loadCount = 0

    func loadPlans() async throws -> [NativeSubscriptionPlan] {
        loadCount += 1
        return [
            NativeSubscriptionPlan(
                id: "ascend_staging_yearly",
                title: "Annual",
                localizedPrice: "$49.99",
                renewalDescription: "Renews yearly.",
                trialDescription: nil
            )
        ]
    }

    func purchase(planID: String) async -> PurchaseResult { .cancelled }
}
