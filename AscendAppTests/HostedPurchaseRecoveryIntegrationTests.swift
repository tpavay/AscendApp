import Foundation
import RevenueCat
import SuperwallKit
import Testing
@testable import AscendApp

@MainActor
@Suite(.serialized)
struct HostedPurchaseRecoveryIntegrationTests {
    @Test
    func productionExecutorControllerAndPresenterRoutePendingToOneSafeGateTerminal() async {
        let harness = makeHarness()
        harness.openHostedPresentation()
        harness.contextStore.record(
            placement: "app_access_gate",
            presentationID: harness.presentationID,
            identity: harness.identity,
            productID: harness.productID
        )

        let execution = await harness.executor.executePurchaseWithContext(
            productID: harness.productID
        ) {
            throw NSError(
                domain: ErrorCode.errorDomain,
                code: ErrorCode.paymentPendingError.rawValue
            )
        }
        let result = await harness.controller.resolveHostedExecution(execution)

        #expect(result == .pending)
        #expect(harness.dismissal.count == 1)
        #expect(harness.coordinator.phase == .pendingApproval)
        #expect(harness.coordinator.disablesPurchase)
        #expect(harness.terminals.count == 1)
        #expect(harness.terminals[0].parameters["gate_attempt_id"] != nil)
        #expect(harness.terminals[0].parameters["provider_outcome"] == .string("pending_approval"))

        harness.presenter.handleDismissForTesting(
            revision: harness.presenterRevision,
            result: .declined
        )
        #expect(harness.terminals.count == 1)

        harness.coordinator.entitlementDidChange(.active(["app_access"]))
        #expect(harness.coordinator.phase == .accessConfirmed)
        #expect(harness.coordinator.showsPurchaseControls == false)
    }

    @Test
    func unconfirmedHostedPurchaseReturnsFailedButDismissesIntoVerificationWithoutRepurchase() async {
        let harness = makeHarness()
        harness.openHostedPresentation()
        harness.contextStore.record(
            placement: "app_access_gate",
            presentationID: harness.presentationID,
            identity: harness.identity,
            productID: harness.productID
        )

        let execution = await harness.executor.executePurchaseWithContext(
            productID: harness.productID
        ) {
            RevenueCatPurchaseExecutor.PurchaseResponse(
                userCancelled: false,
                entitlementState: .inactive
            )
        }
        let result = await harness.controller.resolveHostedExecution(execution)

        guard case .failed(let error) = result else {
            Issue.record("Expected the original entitlement-unconfirmed failure")
            return
        }
        #expect(error is RevenueCatPurchaseControllerError)
        #expect(harness.dismissal.count == 1)
        #expect(harness.coordinator.phase == .verificationUnavailable)
        #expect(harness.coordinator.disablesPurchase)
        #expect(harness.terminals.count == 1)
        #expect(
            harness.terminals[0].parameters["provider_outcome"]
                == .string("verification_unavailable")
        )
    }

    @Test
    func staleOrWrongIdentityRecoveryCannotDismissOrMutateTheCurrentPresentation() async {
        let harness = makeHarness()
        harness.openHostedPresentation()
        let staleContext = RevenueCatPurchaseAnalyticsContext(
            placement: "app_access_gate",
            presentationID: "older-presentation"
        )
        let wrongRevision = MonetizationIdentityTransition(
            revision: harness.identity.revision + 1,
            userID: harness.identity.userID
        )

        #expect(await harness.presenter.recoverHostedPurchase(
            .pendingApproval,
            context: staleContext,
            identity: harness.identity
        ) == false)
        #expect(await harness.presenter.recoverHostedPurchase(
            .pendingApproval,
            context: RevenueCatPurchaseAnalyticsContext(
                placement: "app_access_gate",
                presentationID: harness.presentationID
            ),
            identity: wrongRevision
        ) == false)
        #expect(harness.dismissal.count == 0)
        #expect(harness.coordinator.phase == .hostedPresented)
    }

    @Test
    func cancelledQueuedPresentationDismissesIfStillCurrentButStaleCallbackCannotDismissRetry() async {
        let dismissal = ControlledPresenterDismissal()
        let register = PresenterRegistrationRecorder()
        let controller = RevenueCatPurchaseController(isPurchasesConfigured: { false })
        let presenter = SuperwallPaywallPresenter(
            purchaseController: controller,
            startsConfigured: true,
            registerPlacement: register.register,
            dismissPresentation: dismissal.dismiss
        )
        let identity = MonetizationIdentityTransition(revision: 1, userID: "user-a")
        let oldRevision = presenter.beginPresentationAttemptForTesting(
            identity: identity,
            onOutcome: { _ in }
        )

        presenter.cancelPresentation()
        await dismissal.waitUntilCount(1)
        #expect(presenter.handlePresentationBegan(
            revision: oldRevision,
            presentationID: "late-old"
        ) == false)
        dismissal.resume(call: 1)
        await dismissal.waitUntilCount(2)
        dismissal.resume(call: 2)

        presenter.register(placement: .appAccessGate, identity: identity) { _ in }
        await register.waitUntilCount(1)
        let retryRevision = presenter.beginPresentationAttemptForTesting(
            identity: identity,
            onOutcome: { _ in }
        )
        #expect(presenter.handlePresentationBegan(
            revision: retryRevision,
            presentationID: "retry"
        ))

        let countBeforeStaleCallback = dismissal.count
        #expect(presenter.handlePresentationBegan(
            revision: oldRevision,
            presentationID: "late-old-again"
        ) == false)
        await Task.yield()
        #expect(dismissal.count == countBeforeStaleCallback)
    }

    @Test
    func recoveryDismissalSerializesIdentityChangeAndReplacementRegistration() async {
        let dismissal = ControlledPresenterDismissal()
        let register = PresenterRegistrationRecorder()
        let presenter = SuperwallPaywallPresenter(
            purchaseController: RevenueCatPurchaseController(isPurchasesConfigured: { false }),
            startsConfigured: true,
            registerPlacement: register.register,
            dismissPresentation: dismissal.dismiss
        )
        let identity = MonetizationIdentityTransition(revision: 1, userID: "user-a")
        var outcomes: [PaywallPresentationOutcome] = []
        let recoveringRevision = presenter.beginPresentationAttemptForTesting(
            identity: identity,
            onOutcome: { outcomes.append($0) }
        )
        #expect(presenter.handlePresentationBegan(
            revision: recoveringRevision,
            presentationID: "recovering"
        ))

        let recoveryTask = Task { @MainActor in
            await presenter.recoverHostedPurchase(
                .pendingApproval,
                context: RevenueCatPurchaseAnalyticsContext(
                    placement: "app_access_gate",
                    presentationID: "recovering"
                ),
                identity: identity
            )
        }
        await dismissal.waitUntilCount(1)
        #expect(outcomes == [.pendingApproval])

        presenter.cancelPresentation()
        let replacementIdentity = MonetizationIdentityTransition(revision: 2, userID: "user-b")
        presenter.register(placement: .appAccessGate, identity: replacementIdentity) { _ in }
        await Task.yield()
        #expect(register.count == 0)

        dismissal.resume(call: 1)
        await dismissal.waitUntilCount(2)
        #expect(register.count == 0)
        dismissal.resume(call: 2)
        await register.waitUntilCount(1)
        #expect(await recoveryTask.value)

        let replacementRevision = presenter.beginPresentationAttemptForTesting(
            identity: replacementIdentity,
            onOutcome: { _ in }
        )
        #expect(presenter.handlePresentationBegan(
            revision: replacementRevision,
            presentationID: "replacement"
        ))
        let countBeforeStaleCallback = dismissal.count
        #expect(presenter.handlePresentationBegan(
            revision: recoveringRevision,
            presentationID: "recovering-late"
        ) == false)
        await Task.yield()
        #expect(dismissal.count == countBeforeStaleCallback)
        #expect(outcomes == [.pendingApproval])
    }

    @Test
    func sdkDidPresentBeforeHandlerRecordsShownOnceForTheCapturedAccountOnly() {
        let sink = IdentityAttributingTelemetrySink()
        let telemetry = TelemetryManager(
            sinks: [sink],
            crashlyticsReporter: NoopCrashlyticsReporter(),
            collectionEnabledOverride: true,
            identityStore: makeTestIdentityStore()
        )
        telemetry.configure()
        telemetry.setUserId("user-a")
        let contextStore = PaywallTransactionContextStore()
        let currentLifecycleUserID = CurrentLifecycleUserID("user-a")
        var attemptedLifecycleUserIDs: [String] = []
        var deliveredLifecycleTypes: [String] = []
        let presenter = SuperwallPaywallPresenter(
            purchaseController: RevenueCatPurchaseController(isPurchasesConfigured: { false }),
            telemetry: telemetry,
            transactionContextStore: contextStore,
            startsConfigured: true,
            registerPlacement: { _, _, _ in },
            dismissPresentation: {},
            recordLifecyclePaywallShown: { _, expectedUserID in
                attemptedLifecycleUserIDs.append(expectedUserID)
                if expectedUserID == currentLifecycleUserID.value {
                    deliveredLifecycleTypes.append("shown")
                }
            },
            recordLifecyclePaywallDismissed: { _, _, expectedUserID in
                attemptedLifecycleUserIDs.append(expectedUserID)
                if expectedUserID == currentLifecycleUserID.value {
                    deliveredLifecycleTypes.append("dismissed")
                }
            }
        )
        let identityA = MonetizationIdentityTransition(revision: 1, userID: "user-a")
        let revision = presenter.beginPresentationAttemptForTesting(
            identity: identityA,
            onOutcome: { _ in }
        )
        let context = PaywallAnalyticsContext(
            placement: SuperwallPlacement.appAccessGate.rawValue,
            paywallIdentifier: "gate-paywall",
            paywallName: "Gate",
            presentedBy: "placement",
            isFreeTrialAvailable: true,
            presentationID: "presentation-a",
            dismissReason: "close_button"
        )
        presenter.handlePaywallDidPresentFromDelegate(context: context)
        #expect(sink.attributions.isEmpty)
        #expect(attemptedLifecycleUserIDs.isEmpty)

        #expect(presenter.handlePresentationFromHandler(
            revision: revision,
            context: context
        ))
        #expect(presenter.handlePresentationFromHandler(
            revision: revision,
            context: context
        ))

        telemetry.setUserId("user-b")
        currentLifecycleUserID.value = "user-b"
        _ = presenter.beginPresentationAttemptForTesting(
            identity: MonetizationIdentityTransition(revision: 2, userID: "user-b"),
            onOutcome: { _ in }
        )
        presenter.handlePaywallDidPresentFromDelegate(context: context)
        #expect(presenter.handlePresentationFromHandler(
            revision: revision,
            context: context
        ) == false)
        presenter.handlePaywallDismissed(context: context)
        presenter.handleTransactionStarted(context: context, productID: "ascend_yearly")
        presenter.handleTransactionAbandoned(context: context, productID: "ascend_yearly")

        #expect(sink.attributions.map(\.name) == ["paywall_shown"])
        #expect(sink.attributions.map(\.userID) == ["user-a"])
        #expect(attemptedLifecycleUserIDs == ["user-a", "user-a"])
        #expect(deliveredLifecycleTypes == ["shown"])
        let storedContext = contextStore.takeContext(for: "ascend_yearly")
        #expect(storedContext?.identity == identityA)
        #expect(storedContext?.analytics.presentationID == "presentation-a")
        #expect(sink.attributions.allSatisfy {
            $0.parameters["user_id"] == nil &&
                $0.parameters["identity_revision"] == nil
        })
    }

    // MARK: - A paywall the dashboard chains onto the registered one

    @Test
    func theFirstPaywallClosingForAnOfferEndsNothingAndTheOfferJoinsTheSameAttempt() {
        let harness = makeHarness()
        harness.openHostedPresentation()

        harness.closeFirstPaywallForOffer()
        #expect(harness.coordinator.phase == .openingHosted)
        #expect(harness.terminals.isEmpty)

        harness.openOffer()
        #expect(harness.coordinator.phase == .hostedPresented)
        #expect(harness.coordinator.showsPurchaseControls == false)
        #expect(harness.terminals.isEmpty)
    }

    @Test
    func theOfferFunnelIsReadableAndSaysWhichPaywallItWas() async {
        let harness = makeHarness()
        harness.openHostedPresentation()
        #expect(harness.presenter.handlePresentationFromHandler(
            revision: harness.presenterRevision,
            context: harness.firstPaywallContext
        ))
        harness.closeFirstPaywallForOffer()
        harness.openOffer()

        harness.presenter.handleTransactionStarted(
            context: harness.offerContext,
            productID: "ascend_staging_yearly_welcome"
        )
        harness.presenter.handleTransactionAbandoned(
            context: harness.offerContext,
            productID: "ascend_staging_yearly_welcome"
        )
        harness.presenter.handlePaywallDismissed(context: harness.offerContext)

        let shown = harness.sink.records.filter { $0.name == "paywall_shown" }
        #expect(shown.map { $0.parameters["source"] } == [.string("access_gate"), .string("decline_offer")])
        #expect(shown.last?.parameters["placement"] == .string("paywall_decline"))
        #expect(shown.last?.parameters["paywall_name"] == .string("Decline Offer"))

        for name in ["paywall_transaction_started", "paywall_transaction_abandoned", "paywall_dismissed"] {
            let record = harness.sink.records.first { $0.name == name }
            #expect(record?.parameters["source"] == .string("decline_offer"), "\(name)")
            #expect(record?.parameters["paywall_identifier"] == .string("offer-paywall"), "\(name)")
        }
    }

    @Test
    func anAskToBuyInTheOfferLandsOnTheNonRepurchaseStateAndStaysThereAfterARelaunch() async {
        let harness = makeHarness()
        harness.openHostedPresentation()
        harness.closeFirstPaywallForOffer()
        harness.openOffer()
        harness.presenter.handleTransactionStarted(
            context: harness.offerContext,
            productID: harness.productID
        )

        let execution = await harness.executor.executePurchaseWithContext(
            productID: harness.productID
        ) {
            throw NSError(
                domain: ErrorCode.errorDomain,
                code: ErrorCode.paymentPendingError.rawValue
            )
        }
        let result = await harness.controller.resolveHostedExecution(execution)

        #expect(result == .pending)
        #expect(harness.dismissal.count == 1)
        #expect(harness.coordinator.phase == .pendingApproval)
        #expect(harness.coordinator.disablesPurchase)
        #expect(harness.sink.records.contains { $0.name == "hosted_purchase_recovery_refused" } == false)
        #expect(harness.manager.pendingPurchaseHold == .askToBuy)

        let relaunched = harness.relaunchedCoordinator()
        relaunched.start()
        #expect(relaunched.phase == .pendingApproval)
        #expect(relaunched.showsPurchaseControls == false)
        await harness.presenter.drainPresentationOperationsForTesting()
        #expect(harness.registrations.isEmpty, "a relaunch under a hold opens no paywall")
    }

    @Test
    func anUnconfirmedChargeInTheOfferLandsOnTheNonRepurchaseStateAndStaysThereAfterARelaunch() async {
        let harness = makeHarness()
        harness.openHostedPresentation()
        harness.closeFirstPaywallForOffer()
        harness.openOffer()
        harness.presenter.handleTransactionStarted(
            context: harness.offerContext,
            productID: harness.productID
        )

        let execution = await harness.executor.executePurchaseWithContext(
            productID: harness.productID
        ) {
            RevenueCatPurchaseExecutor.PurchaseResponse(
                userCancelled: false,
                entitlementState: .inactive
            )
        }
        let result = await harness.controller.resolveHostedExecution(execution)

        guard case .failed = result else {
            Issue.record("Expected the entitlement-unconfirmed failure")
            return
        }
        #expect(harness.dismissal.count == 1)
        #expect(harness.coordinator.phase == .verificationUnavailable)
        #expect(harness.manager.pendingPurchaseHold == .unconfirmedCharge)

        let relaunched = harness.relaunchedCoordinator()
        relaunched.start()
        #expect(relaunched.phase == .verificationUnavailable)
        #expect(relaunched.showsPurchaseControls == false)
    }

    @Test
    func aHoldTheGateNeverHeardAboutStillRefusesThePlanListWhenThePaywallCloses() {
        let harness = makeHarness()
        harness.openHostedPresentation()
        harness.manager.holdPendingPurchase(.unconfirmedCharge)

        harness.presenter.handleDismissForTesting(
            revision: harness.presenterRevision,
            result: .declined
        )

        #expect(harness.coordinator.phase == .verificationUnavailable)
        #expect(harness.coordinator.showsPurchaseControls == false)
        #expect(harness.coordinator.disablesPurchase)
        #expect(harness.terminals.last?.parameters["provider_outcome"] == .string("verification_unavailable"))
    }

    @Test
    func aPurchaseThatNeverReachedAppleLeavesNoHold() async {
        let harness = makeHarness(identityMatchesPurchase: false)
        let execution = await harness.executor.executePurchaseWithContext(
            productID: harness.productID
        ) {
            RevenueCatPurchaseExecutor.PurchaseResponse(userCancelled: false)
        }

        guard case .failed = execution.result else {
            Issue.record("Expected a refusal before RevenueCat was called")
            return
        }
        #expect(harness.manager.pendingPurchaseHold == nil)
    }

    @Test
    func closingTheOfferWithoutBuyingLandsOnThePlanListOnlyWhenNothingIsHeld() async {
        let harness = makeHarness()
        harness.openHostedPresentation()
        harness.closeFirstPaywallForOffer()
        harness.openOffer()

        harness.presenter.handleDismissForTesting(
            revision: harness.presenterRevision,
            result: .declined
        )

        #expect(harness.coordinator.phase == .loadingNative)
        #expect(harness.coordinator.statusMessage == "No purchase was made. Choose a plan below.")
    }

    @Test
    func theOfferNeverOpeningFallsBackRatherThanStrandingTheClimber() async {
        let harness = makeHarness(watchdogFires: true)
        harness.openHostedPresentation()

        harness.closeFirstPaywallForOffer()

        await waitUntil { harness.coordinator.phase != .openingHosted }
        #expect(harness.coordinator.phase == .loadingNative || harness.coordinator.phase == .failed)
        await waitUntil { harness.dismissal.count > 0 }
    }

    @Test
    func deleteAccountOnTheOfferReachesTheAttemptOwner() async {
        var deletionRequests = 0
        let harness = makeHarness(onRequestAccountDeletion: { deletionRequests += 1 })
        harness.openHostedPresentation()
        harness.closeFirstPaywallForOffer()
        harness.openOffer()

        harness.presenter.handleCustomPaywallAction(withName: SuperwallCustomAction.deleteAccount.rawValue)
        await harness.presenter.drainPresentationOperationsForTesting()

        #expect(harness.dismissal.count == 1)
        #expect(deletionRequests == 1)
    }

    @Test
    func aRestoreThatFindsNothingEndsAnAskToBuyHoldButNeverAChargeHold() async {
        let cases: [(PendingPurchaseHold, PendingPurchaseHold?, AppAccessGatePhase)] = [
            (.askToBuy, nil, .failed),
            (.unconfirmedCharge, .unconfirmedCharge, .verificationUnavailable)
        ]
        for (hold, expectedHold, expectedPhase) in cases {
            let harness = makeHarness()
            harness.manager.holdPendingPurchase(hold)
            let gate = harness.relaunchedCoordinator()
            gate.start()

            gate.restore()
            await waitUntil { gate.restoreState != .restoring }

            #expect(harness.manager.pendingPurchaseHold == expectedHold)
            #expect(gate.phase == expectedPhase)
        }
    }

    @Test
    func accessArrivingEndsTheHoldAndAHoldCannotBeWrittenOverAccess() {
        let entitlements = HostedEntitlementService(
            identity: MonetizationIdentityTransition(revision: 1, userID: "hosted-user")
        )
        let telemetry = makeTestTelemetry(sink: InMemoryTelemetrySink(destination: .analytics))
        let manager = MonetizationManager(
            configuration: HostedHarness.configuration,
            entitlementService: entitlements,
            paywallPresenter: PaywallPresenterSpy(),
            telemetry: telemetry,
            onboardingLifecycle: makeScratchOnboardingLifecycle(telemetry: telemetry),
            userDefaults: UserDefaults(
                suiteName: "HostedPurchaseRecoveryIntegrationTests-\(UUID().uuidString)"
            )!
        )
        manager.configure(configuration: HostedHarness.configuration)
        manager.holdPendingPurchase(.askToBuy)
        #expect(manager.pendingPurchaseHold == .askToBuy)

        entitlements.publish(.active(["app_access"]))
        #expect(manager.pendingPurchaseHold == nil)

        manager.holdPendingPurchase(.unconfirmedCharge)
        #expect(manager.pendingPurchaseHold == nil)
    }

    private func makeHarness(
        identityMatchesPurchase: Bool = true,
        watchdogFires: Bool = false,
        onRequestAccountDeletion: (@MainActor () -> Void)? = nil
    ) -> HostedHarness {
        let identity = MonetizationIdentityTransition(revision: 41, userID: "hosted-user")
        let contextStore = PaywallTransactionContextStore()
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)
        telemetry.setUserId("hosted-user")
        let router = HostedRecoveryRouterBox()
        let executor = RevenueCatPurchaseExecutor(
            telemetry: telemetry,
            transactionContextStore: contextStore,
            entitlementID: "app_access",
            applySubscriptionStatus: { _ in },
            refreshEntitlementState: { .refreshed(.inactive) },
            currentIdentityGeneration: { identityMatchesPurchase ? identity : nil },
            adoptEntitlementState: { _, candidate in candidate == identity },
            holdPendingPurchase: { router.manager?.holdPendingPurchase($0) }
        )
        let controller = RevenueCatPurchaseController(
            executor: executor,
            isPurchasesConfigured: { false },
            recoveryRouter: router.route
        )
        let dismissal = ImmediatePresenterDismissal()
        let registrations = RegisteredPlacements()
        let presenter = SuperwallPaywallPresenter(
            purchaseController: controller,
            telemetry: telemetry,
            transactionContextStore: contextStore,
            startsConfigured: true,
            registerPlacement: { placement, _, _ in registrations.record(placement) },
            dismissPresentation: dismissal.dismiss
        )
        router.presenter = presenter
        let entitlements = HostedEntitlementService(identity: identity)
        let manager = MonetizationManager(
            configuration: HostedHarness.configuration,
            entitlementService: entitlements,
            paywallPresenter: presenter,
            telemetry: telemetry,
            onboardingLifecycle: makeScratchOnboardingLifecycle(telemetry: telemetry),
            userDefaults: UserDefaults(
                suiteName: "HostedPurchaseRecoveryIntegrationTests-\(UUID().uuidString)"
            )!
        )
        router.manager = manager
        let makeCoordinator: @MainActor () -> AppAccessPaywallCoordinator = {
            AppAccessPaywallCoordinator(
                monetizationManager: manager,
                nativeProvider: HostedNativeProvider(),
                restoreService: AppAccessRestoreService(
                    telemetry: telemetry,
                    entitlementID: "app_access",
                    restorer: { manager }
                ),
                telemetry: telemetry,
                onRequestAccountDeletion: onRequestAccountDeletion,
                sleep: { @Sendable _ in
                    guard !watchdogFires else { return }
                    try await Task.sleep(for: .seconds(3_600))
                },
                nativeLoadSleep: { _ in try await Task.sleep(for: .seconds(3_600)) }
            )
        }
        let presentationID = "presentation-123"
        return HostedHarness(
            identity: identity,
            presentationID: presentationID,
            productID: "ascend_staging_yearly",
            coordinator: makeCoordinator(),
            makeCoordinator: makeCoordinator,
            manager: manager,
            entitlements: entitlements,
            presenter: presenter,
            controller: controller,
            executor: executor,
            contextStore: contextStore,
            dismissal: dismissal,
            sink: sink,
            registrationRecorder: registrations
        )
    }
}

@MainActor
private final class CurrentLifecycleUserID {
    var value: String

    init(_ value: String) {
        self.value = value
    }
}

@MainActor
private final class HostedHarness {
    static let configuration = MonetizationConfiguration(infoDictionary: [
        MonetizationConfiguration.revenueCatAPIKeyInfoKey: "appl_test",
        MonetizationConfiguration.superwallAPIKeyInfoKey: "pk_test",
        MonetizationConfiguration.revenueCatYearlyProductIDInfoKey: "ascend_staging_yearly",
        MonetizationConfiguration.revenueCatLifetimeProductIDInfoKey: "ascend_staging_lifetime",
        MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "NO"
    ])

    let identity: MonetizationIdentityTransition
    let presentationID: String
    private(set) var presenterRevision: UInt = 0
    let productID: String
    let coordinator: AppAccessPaywallCoordinator
    private let makeCoordinator: @MainActor () -> AppAccessPaywallCoordinator
    let manager: MonetizationManager
    let entitlements: HostedEntitlementService
    let presenter: SuperwallPaywallPresenter
    let controller: RevenueCatPurchaseController
    let executor: RevenueCatPurchaseExecutor
    let contextStore: PaywallTransactionContextStore
    let dismissal: ImmediatePresenterDismissal
    let sink: InMemoryTelemetrySink
    private let registrationRecorder: RegisteredPlacements

    let firstPaywallContext: PaywallAnalyticsContext
    let offerContext = PaywallAnalyticsContext(
        placement: "paywall_decline",
        paywallIdentifier: "offer-paywall",
        paywallName: "Decline Offer",
        presentedBy: "placement",
        isFreeTrialAvailable: true,
        presentationID: "offer-presentation",
        dismissReason: "manualClose"
    )

    init(
        identity: MonetizationIdentityTransition,
        presentationID: String,
        productID: String,
        coordinator: AppAccessPaywallCoordinator,
        makeCoordinator: @escaping @MainActor () -> AppAccessPaywallCoordinator,
        manager: MonetizationManager,
        entitlements: HostedEntitlementService,
        presenter: SuperwallPaywallPresenter,
        controller: RevenueCatPurchaseController,
        executor: RevenueCatPurchaseExecutor,
        contextStore: PaywallTransactionContextStore,
        dismissal: ImmediatePresenterDismissal,
        sink: InMemoryTelemetrySink,
        registrationRecorder: RegisteredPlacements
    ) {
        self.identity = identity
        self.presentationID = presentationID
        self.productID = productID
        self.coordinator = coordinator
        self.makeCoordinator = makeCoordinator
        self.manager = manager
        self.entitlements = entitlements
        self.registrationRecorder = registrationRecorder
        firstPaywallContext = PaywallAnalyticsContext(
            placement: SuperwallPlacement.appAccessGate.rawValue,
            paywallIdentifier: "gate-paywall",
            paywallName: "Gate",
            presentedBy: "placement",
            isFreeTrialAvailable: true,
            presentationID: presentationID
        )
        self.presenter = presenter
        self.controller = controller
        self.executor = executor
        self.contextStore = contextStore
        self.dismissal = dismissal
        self.sink = sink
    }

    var terminals: [EnvelopedTelemetryRecord] {
        sink.records.filter { $0.name == "app_access_gate_attempt_terminal" }
    }

    func openHostedPresentation() {
        coordinator.start()
        coordinator.handleHostedOutcomeForTesting(.presented)
        presenterRevision = presenter.beginPresentationAttemptForTesting(
            identity: identity,
            onOutcome: { [weak coordinator] outcome in
                coordinator?.handleHostedOutcomeForTesting(outcome)
            }
        )
        #expect(presenter.handlePresentationBegan(
            revision: presenterRevision,
            presentationID: presentationID
        ))
        #expect(coordinator.phase == .hostedPresented)
    }

    /// What SuperwallKit does once a `paywall_decline` campaign matches: the first paywall reports a
    /// declined dismissal with `forNextPaywall`, and the next one presents through the same handler.
    func closeFirstPaywallForOffer() {
        presenter.handleDismissForTesting(
            revision: presenterRevision,
            result: .declined,
            closeReason: .forNextPaywall
        )
    }

    func openOffer() {
        #expect(presenter.handlePresentationFromHandler(
            revision: presenterRevision,
            context: offerContext
        ))
        coordinator.handleHostedOutcomeForTesting(.presented)
    }

    func relaunchedCoordinator() -> AppAccessPaywallCoordinator {
        makeCoordinator()
    }

    var registrations: [String] { registrationRecorder.placements }
}

@MainActor
private final class RegisteredPlacements {
    private(set) var placements: [String] = []
    func record(_ placement: String) { placements.append(placement) }
}

@MainActor
private final class HostedRecoveryRouterBox {
    weak var presenter: SuperwallPaywallPresenter?
    weak var manager: MonetizationManager?

    func route(
        recovery: HostedPurchaseRecovery,
        context: RevenueCatPurchaseAnalyticsContext,
        identity: MonetizationIdentityTransition
    ) async -> Bool {
        guard let presenter else { return false }
        return await presenter.recoverHostedPurchase(
            recovery,
            context: context,
            identity: identity
        )
    }
}

@MainActor
private final class ImmediatePresenterDismissal {
    private(set) var count = 0
    func dismiss() async { count += 1 }
}

@MainActor
private final class ControlledPresenterDismissal {
    private(set) var count = 0
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var observers: [CheckedContinuation<Void, Never>] = []

    func dismiss() async {
        count += 1
        observers.forEach { $0.resume() }
        observers = []
        await withCheckedContinuation { continuations[count] = $0 }
    }

    func waitUntilCount(_ expected: Int) async {
        if count >= expected { return }
        await withCheckedContinuation { observers.append($0) }
        if count < expected { await waitUntilCount(expected) }
    }

    func resume(call: Int) {
        continuations.removeValue(forKey: call)?.resume()
    }
}

@MainActor
private final class PresenterRegistrationRecorder {
    private(set) var count = 0
    private var observers: [CheckedContinuation<Void, Never>] = []

    func register(
        placement: String,
        params: [String: Any]?,
        handler: PaywallPresentationHandler
    ) {
        count += 1
        observers.forEach { $0.resume() }
        observers = []
    }

    func waitUntilCount(_ expected: Int) async {
        if count >= expected { return }
        await withCheckedContinuation { observers.append($0) }
        if count < expected { await waitUntilCount(expected) }
    }
}

@MainActor
private final class HostedEntitlementService: EntitlementServicing {
    var entitlementState: MonetizationEntitlementState = .inactive
    var hasFailedIdentityResolution = false
    var identityGeneration: MonetizationIdentityTransition?
    var isConfigured = true

    private var observer: (@MainActor (MonetizationEntitlementState) -> Void)?

    init(identity: MonetizationIdentityTransition) { identityGeneration = identity }
    func configure(configuration: MonetizationConfiguration) {}
    func setEntitlementStateObserver(
        _ observer: (@MainActor (MonetizationEntitlementState) -> Void)?
    ) {
        self.observer = observer
    }
    func publish(_ state: MonetizationEntitlementState) {
        entitlementState = state
        observer?(state)
    }
    func refreshCustomerInfo(waitsForPendingIdentity: Bool) async -> MonetizationEntitlementRefresh {
        .refreshed(entitlementState)
    }
    func prepareIdentity(_ customer: MonetizationCustomerIdentity) -> MonetizationIdentityTransition {
        identityGeneration!
    }
    func identify(_ customer: MonetizationCustomerIdentity, transition: MonetizationIdentityTransition) async {}
    func prepareIdentityReset() -> MonetizationIdentityTransition { .init(revision: 0, userID: nil) }
    func resetIdentity(transition: MonetizationIdentityTransition) async {}
    func retryIdentityResolution() async {}
    func adoptTransactionState(_ state: MonetizationEntitlementState, for identity: MonetizationIdentityTransition) -> Bool {
        guard identityGeneration == identity else { return false }
        entitlementState = state
        return true
    }
    func restorePurchases(for identity: MonetizationIdentityTransition) async -> MonetizationEntitlementState { entitlementState }
    func restorePurchases() async -> MonetizationEntitlementState { entitlementState }
}

@MainActor
private final class HostedNativeProvider: NativePaywallPlanProviding {
    func loadPlans() async throws -> [NativePaywallPlan] { [] }
    func purchase(planID: String) async -> PurchaseResult { .cancelled }
}

@MainActor
private func waitUntil(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<500 where !condition() {
        try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition())
}
