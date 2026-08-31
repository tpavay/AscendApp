import Foundation
import os
import SuperwallKit

@MainActor
final class SuperwallPaywallPresenter: PaywallPresenting {
    static let shared = SuperwallPaywallPresenter()
    private static let logger = Logger(subsystem: "com.ascendapp.app", category: "Paywall")

    private(set) var isConfigured = false
    private let transactionContextStore: PaywallTransactionContextStore
    private let telemetry: TelemetryManager
    private let purchaseController: RevenueCatPurchaseController
    private let attemptRegistry: SuperwallPresentationAttemptRegistry
    private let recordLifecyclePaywallShown: @MainActor (String, String) -> Void
    private let recordLifecyclePaywallDismissed: @MainActor (String, String?, String) -> Void
    private let dismissPresentation: @MainActor @Sendable () async -> Void
    private let registerPlacement: @MainActor (
        String,
        [String: Any]?,
        PaywallPresentationHandler
    ) -> Void
    private struct Registration {
        let placement: String
        let identity: MonetizationIdentityTransition?
        let gateAttemptID: String?
        let onOutcome: @MainActor (PaywallPresentationOutcome) -> Void
    }
    private struct PresentedToken {
        let revision: UInt
        let presentationID: String
        let placement: String
        let identity: MonetizationIdentityTransition
        let gateAttemptID: String?
        let onOutcome: @MainActor (PaywallPresentationOutcome) -> Void
        var recoveryOwned: Bool
        /// The last `Custom action` name this presentation reported, if any.
        ///
        /// A custom action does not dismiss the paywall, so the name is banked here and read when
        /// the dismissal arrives. Deliberately not acted on at arrival: SuperwallKit re-dispatches
        /// every web event through an unstructured `Task`, so the custom action landing before the
        /// close is observed behaviour rather than a contract.
        var latchedActionName: String?
    }
    private struct PresentationTelemetryOwner {
        let identity: MonetizationIdentityTransition?
    }
    private var registrations: [UInt: Registration] = [:]
    private var presentedToken: PresentedToken?
    private var telemetryOwnersByPresentationID: [String: PresentationTelemetryOwner] = [:]
    private var telemetryPresentationOrder: [String] = []
    private var shownPresentationIDs: Set<String> = []
    private var presentationOperationTail: Task<Void, Never>?
    private var registrationTask: Task<Void, Never>?

    init(
        purchaseController: RevenueCatPurchaseController = RevenueCatPurchaseController(),
        telemetry: TelemetryManager = .shared,
        transactionContextStore: PaywallTransactionContextStore = .shared,
        attemptRegistry: SuperwallPresentationAttemptRegistry = SuperwallPresentationAttemptRegistry(),
        startsConfigured: Bool = false,
        registerPlacement: @escaping @MainActor (
            String,
            [String: Any]?,
            PaywallPresentationHandler
        ) -> Void = { placement, params, handler in
            Superwall.shared.register(
                placement: placement,
                params: params,
                handler: handler,
                feature: {}
            )
        },
        dismissPresentation: @escaping @MainActor @Sendable () async -> Void = {
            await Superwall.shared.dismiss()
        },
        recordLifecyclePaywallShown: @escaping @MainActor (String, String) -> Void = {
            LifecycleEventRecorder.shared.recordPaywallShown(
                placement: $0,
                expectedUserID: $1
            )
        },
        recordLifecyclePaywallDismissed: @escaping @MainActor (
            String,
            String?,
            String
        ) -> Void = {
            LifecycleEventRecorder.shared.recordPaywallDismissed(
                placement: $0,
                reason: $1,
                expectedUserID: $2
            )
        }
    ) {
        self.purchaseController = purchaseController
        self.telemetry = telemetry
        self.transactionContextStore = transactionContextStore
        self.attemptRegistry = attemptRegistry
        isConfigured = startsConfigured
        self.registerPlacement = registerPlacement
        self.dismissPresentation = dismissPresentation
        self.recordLifecyclePaywallShown = recordLifecyclePaywallShown
        self.recordLifecyclePaywallDismissed = recordLifecyclePaywallDismissed
    }

    func configure(configuration: MonetizationConfiguration = .live) {
        guard !isConfigured else { return }
        guard configuration.revenueCatAPIKey != nil else { return }
        guard let apiKey = configuration.superwallAPIKey else { return }

        let options = SuperwallOptions()
        options.testModeBehavior = configuration.isSuperwallTestModeEnabled ? .always : .never
        options.paywalls.shouldShowPurchaseFailureAlert = false

        Superwall.configure(
            apiKey: apiKey,
            purchaseController: purchaseController,
            options: options
        )
        Superwall.shared.delegate = self
        isConfigured = true
    }

    func updateSubscriptionStatus(entitlementIDs: Set<String>) {
        guard isConfigured else { return }
        Superwall.shared.subscriptionStatus = RevenueCatPurchaseController.subscriptionStatus(
            for: entitlementIDs
        )
    }

    func identify(userId: String) {
        guard isConfigured else { return }
        Superwall.shared.identify(userId: userId)
    }

    func resetIdentity() {
        guard isConfigured else { return }
        Superwall.shared.reset()
    }

    func cancelPresentation() {
        let revision = attemptRegistry.currentRevision
        attemptRegistry.cancelCurrent()
        if presentedToken?.revision == revision {
            presentedToken = nil
        }
        registrations[revision] = nil
        registrationTask?.cancel()
        guard isConfigured else { return }
        enqueueDismissal()
    }

    func register(
        placement: SuperwallPlacement,
        params: [String: Any]? = nil,
        onOutcome: @escaping @MainActor (PaywallPresentationOutcome) -> Void
    ) {
        registerInternal(
            placement: placement,
            params: params,
            identity: nil,
            onOutcome: onOutcome
        )
    }

    func register(
        placement: SuperwallPlacement,
        params: [String: Any]? = nil,
        identity: MonetizationIdentityTransition,
        onOutcome: @escaping @MainActor (PaywallPresentationOutcome) -> Void
    ) {
        registerInternal(
            placement: placement,
            params: params,
            identity: identity,
            onOutcome: onOutcome
        )
    }

    private func registerInternal(
        placement: SuperwallPlacement,
        params: [String: Any]?,
        identity: MonetizationIdentityTransition?,
        onOutcome: @escaping @MainActor (PaywallPresentationOutcome) -> Void
    ) {
        guard isConfigured else { return }
        let revision = attemptRegistry.begin()
        registrations[revision] = Registration(
            placement: placement.rawValue,
            identity: identity,
            gateAttemptID: params?["gate_attempt_id"] as? String,
            onOutcome: onOutcome
        )
        let handler = makePresentationHandler(
            for: placement,
            revision: revision,
            onOutcome: onOutcome
        )

        registrationTask?.cancel()
        registrationTask = enqueuePresentationOperation { [weak self] in
            guard !Task.isCancelled,
                  let self,
                  self.attemptRegistry.isAuthoritative(revision) else { return }
            self.registerPlacement(placement.rawValue, params, handler)
        }
    }

    private func makePresentationHandler(
        for placement: SuperwallPlacement,
        revision: UInt,
        onOutcome: @escaping @MainActor (PaywallPresentationOutcome) -> Void
    ) -> PaywallPresentationHandler {
        let handler = PaywallPresentationHandler()

        handler.onPresent { paywallInfo in
            let context = PaywallAnalyticsContext(paywallInfo: paywallInfo)
            guard self.handlePresentationFromHandler(
                revision: revision,
                context: context
            ) else { return }
            onOutcome(.presented)
        }

        handler.onDismiss { _, result in
            self.handleDismiss(
                revision: revision,
                result: result,
                onOutcome: onOutcome
            )
        }

        handler.onSkip { reason in
            guard self.attemptRegistry.isAuthoritative(revision) else { return }
            guard let registration = self.registrations[revision] else { return }
            let category = SuperwallSkipReasonCategory.classify(String(describing: reason))
            Self.logger.warning("Superwall skipped placement \(placement.rawValue, privacy: .public): \(category.rawValue, privacy: .public)")
            self.track(
                PaywallAnalyticsEvent.diagnosticRecord(
                    name: "paywall_skipped",
                    parameters: [
                        "placement": .string(placement.rawValue),
                        "reason": .string(category.rawValue)
                    ]
                ),
                identity: registration.identity
            )
            onOutcome(.skipped(reason: category.rawValue))
            self.registrations[revision] = nil
        }

        handler.onError { error in
            guard self.attemptRegistry.isAuthoritative(revision) else { return }
            guard let registration = self.registrations[revision] else { return }
            Self.logger.error("Superwall failed placement \(placement.rawValue, privacy: .public)")
            self.track(
                PaywallAnalyticsEvent.diagnosticRecord(
                    name: "paywall_error",
                    parameters: [
                        "placement": .string(placement.rawValue),
                        "error_type": .string("presentation_error")
                    ]
                ),
                identity: registration.identity
            )
            onOutcome(.failed(message: "Subscription options could not open."))
            self.registrations[revision] = nil
        }

        return handler
    }

    @discardableResult
    func handlePresentationBegan(
        revision: UInt,
        presentationID: String? = nil
    ) -> Bool {
        switch attemptRegistry.authority(of: revision) {
        case .stale:
            // The SDK's dismiss API is global. A stale callback must not dismiss a newer paywall.
            return false
        case .cancelledCurrent:
            enqueueDismissal()
            return false
        case .current:
            break
        }
        if let registration = registrations[revision], let presentationID {
            rememberTelemetryOwner(
                PresentationTelemetryOwner(identity: registration.identity),
                for: presentationID
            )
        }
        if let registration = registrations[revision],
           let identity = registration.identity,
           let presentationID {
            presentedToken = PresentedToken(
                revision: revision,
                presentationID: presentationID,
                placement: registration.placement,
                identity: identity,
                gateAttemptID: registration.gateAttemptID,
                onOutcome: registration.onOutcome,
                recoveryOwned: false,
                latchedActionName: nil
            )
        }
        return true
    }

    @discardableResult
    func handlePresentationFromHandler(
        revision: UInt,
        context: PaywallAnalyticsContext
    ) -> Bool {
        guard handlePresentationBegan(
            revision: revision,
            presentationID: context.presentationID
        ) else {
            return false
        }
        handlePaywallShown(context: context)
        return true
    }

    func beginPresentationAttemptForTesting() -> UInt {
        attemptRegistry.begin()
    }

    func beginPresentationAttemptForTesting(
        identity: MonetizationIdentityTransition,
        onOutcome: @escaping @MainActor (PaywallPresentationOutcome) -> Void
    ) -> UInt {
        let revision = attemptRegistry.begin()
        registrations[revision] = Registration(
            placement: SuperwallPlacement.appAccessGate.rawValue,
            identity: identity,
            gateAttemptID: nil,
            onOutcome: onOutcome
        )
        return revision
    }

    func latchedActionNameForTesting() -> String? {
        presentedToken?.latchedActionName
    }

    func handleDismissForTesting(revision: UInt, result: PaywallResult) {
        guard let registration = registrations[revision] else { return }
        handleDismiss(
            revision: revision,
            result: result,
            onOutcome: registration.onOutcome
        )
    }

    func makeHostedRestoreAnalyticsContext() -> AppAccessRestoreAnalyticsContext {
        guard let token = presentedToken,
              attemptRegistry.isAuthoritative(token.revision) else {
            return .hostedPaywall(
                placement: nil,
                presentationID: nil,
                gateAttemptID: nil
            )
        }
        return .hostedPaywall(
            placement: token.placement,
            presentationID: token.presentationID,
            gateAttemptID: token.gateAttemptID,
            identity: token.identity
        )
    }

    private func handleDismiss(
        revision: UInt,
        result: PaywallResult,
        onOutcome: @escaping @MainActor (PaywallPresentationOutcome) -> Void
    ) {
        guard attemptRegistry.isAuthoritative(revision) else { return }
        if presentedToken?.revision == revision,
           presentedToken?.recoveryOwned == true {
            presentedToken = nil
            registrations[revision] = nil
            return
        }
        switch result {
        case .purchased:
            onOutcome(.purchased)
        case .restored:
            onOutcome(.restored)
        case .declined:
            // Every user-driven close arrives here identically, so the latched custom action is the
            // only thing that separates a deliberate back tap from any other dismissal.
            let latchedActionName = presentedToken?.revision == revision
                ? presentedToken?.latchedActionName
                : nil
            onOutcome(PaywallDismissIntent.resolve(latchedActionName: latchedActionName).outcome)
        }
        presentedToken = nil
        registrations[revision] = nil
    }
}

private extension SuperwallPaywallPresenter {
    private func rememberTelemetryOwner(
        _ owner: PresentationTelemetryOwner,
        for presentationID: String
    ) {
        if telemetryOwnersByPresentationID[presentationID] == nil {
            telemetryPresentationOrder.append(presentationID)
        }
        telemetryOwnersByPresentationID[presentationID] = owner

        // Keep enough completed presentations for late SDK callbacks without growing for the
        // lifetime of a long-running app process.
        while telemetryPresentationOrder.count > 32 {
            let retiredID = telemetryPresentationOrder.removeFirst()
            telemetryOwnersByPresentationID[retiredID] = nil
            shownPresentationIDs.remove(retiredID)
        }
    }

    private func telemetryOwner(for presentationID: String?) -> PresentationTelemetryOwner? {
        guard let presentationID else { return nil }
        return telemetryOwnersByPresentationID[presentationID]
    }

    private func track(
        _ event: any TelemetryEvent,
        identity: MonetizationIdentityTransition?
    ) {
        guard let identity else {
            telemetry.track(event)
            return
        }
        guard let userID = identity.userID else { return }
        telemetry.track(event, ifIdentifiedAs: userID)
    }

    private func track(
        _ record: TelemetryRecord,
        identity: MonetizationIdentityTransition?
    ) {
        guard let identity else {
            telemetry.track(record)
            return
        }
        guard let userID = identity.userID else { return }
        telemetry.track(record, ifIdentifiedAs: userID)
    }

    private func track(
        _ event: any TelemetryEvent,
        owner: PresentationTelemetryOwner
    ) {
        track(event, identity: owner.identity)
    }

    private func track(
        _ event: any TelemetryEvent,
        presentationID: String?
    ) {
        guard let owner = telemetryOwner(for: presentationID) else { return }
        track(event, owner: owner)
    }
}

extension SuperwallPaywallPresenter: HostedPurchaseRecoveryRouting {
    func recoverHostedPurchase(
        _ recovery: HostedPurchaseRecovery,
        context: RevenueCatPurchaseAnalyticsContext,
        identity: MonetizationIdentityTransition
    ) async -> Bool {
        guard let presentationID = context.presentationID else {
            trackRecoveryRefusal("missing_presentation_id", identity: identity)
            return false
        }
        guard var token = presentedToken,
              token.presentationID == presentationID,
              token.identity == identity,
              attemptRegistry.isAuthoritative(token.revision),
              !token.recoveryOwned else {
            trackRecoveryRefusal("stale_or_missing_token", identity: identity)
            return false
        }

        token.recoveryOwned = true
        presentedToken = token
        token.onOutcome(
            recovery == .pendingApproval ? .pendingApproval : .verificationUnavailable
        )
        await enqueueDismissal().value
        return true
    }

    private func trackRecoveryRefusal(
        _ reason: String,
        identity: MonetizationIdentityTransition
    ) {
        track(
            TelemetryRecord(
                name: "hosted_purchase_recovery_refused",
                parameters: ["reason": .string(reason)]
            ),
            identity: identity
        )
    }
}

private extension SuperwallPaywallPresenter {
    @discardableResult
    func enqueueDismissal() -> Task<Void, Never> {
        enqueuePresentationOperation { [dismissPresentation] in
            await dismissPresentation()
        }
    }

    @discardableResult
    func enqueuePresentationOperation(
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) -> Task<Void, Never> {
        let priorOperation = presentationOperationTail
        let task = Task { @MainActor in
            await priorOperation?.value
            await operation()
        }
        presentationOperationTail = task
        return task
    }
}

extension SuperwallPaywallPresenter: SuperwallDelegate {
    func didPresentPaywall(withInfo paywallInfo: PaywallInfo) {
        handlePaywallDidPresentFromDelegate(
            context: PaywallAnalyticsContext(paywallInfo: paywallInfo)
        )
    }

    func didDismissPaywall(withInfo paywallInfo: PaywallInfo) {
        handlePaywallDismissed(context: PaywallAnalyticsContext(paywallInfo: paywallInfo))
    }

    /// Banks the name of a `Custom action` tap so the dismissal that follows can be told apart from
    /// an ordinary close. Superwall keeps the paywall presented across this call, so nothing is
    /// routed here - see ``PaywallDismissIntent``.
    func handleCustomPaywallAction(withName name: String) {
        guard var token = presentedToken,
              attemptRegistry.isAuthoritative(token.revision) else { return }

        token.latchedActionName = name
        presentedToken = token
    }

    func handleSuperwallEvent(withInfo eventInfo: SuperwallEventInfo) {
        switch eventInfo.event {
        case .transactionStart(let product, let paywallInfo):
            handleTransactionStarted(
                context: PaywallAnalyticsContext(paywallInfo: paywallInfo),
                productID: product.productIdentifier
            )

        case .transactionComplete(_, let product, let transactionType, let paywallInfo):
            let context = PaywallAnalyticsContext(paywallInfo: paywallInfo)
            track(
                PaywallAnalyticsEvent.transactionCompleted(
                    context: context,
                    productID: product.productIdentifier,
                    transactionType: transactionType.description
                ),
                presentationID: context.presentationID
            )

        case .transactionFail(let error, let paywallInfo):
            let context = PaywallAnalyticsContext(paywallInfo: paywallInfo)
            track(
                PaywallAnalyticsEvent.transactionFailed(
                    context: context,
                    errorType: error.analyticsType,
                    productID: error.analyticsProductID
                ),
                presentationID: context.presentationID
            )

        case .transactionAbandon(let product, let paywallInfo):
            handleTransactionAbandoned(
                context: PaywallAnalyticsContext(paywallInfo: paywallInfo),
                productID: product.productIdentifier
            )

        case .transactionRestore(let restoreType, let paywallInfo):
            let context = PaywallAnalyticsContext(paywallInfo: paywallInfo)
            track(
                PaywallAnalyticsEvent.restoreCompleted(
                    context: context,
                    restoreType: restoreType.analyticsType
                ),
                presentationID: context.presentationID
            )

        default:
            break
        }
    }

    func handlePaywallDidPresentFromDelegate(context _: PaywallAnalyticsContext) {
        // Superwall invokes this delegate before its onPresent handler. The
        // handler owns shown recording because it also carries the attempt
        // revision needed to bind the captured account first.
    }

    func handlePaywallShown(context: PaywallAnalyticsContext) {
        guard let presentationID = context.presentationID,
              let owner = telemetryOwner(for: presentationID),
              shownPresentationIDs.insert(presentationID).inserted else {
            return
        }
        track(
            PaywallAnalyticsEvent.shown(context: context),
            owner: owner
        )
        guard SuperwallPlacement(rawValue: context.placement) != nil,
              let userID = owner.identity?.userID else {
            return
        }
        recordLifecyclePaywallShown(context.placement, userID)
    }

    func handlePaywallDismissed(context: PaywallAnalyticsContext) {
        track(
            PaywallAnalyticsEvent.dismissed(context: context),
            presentationID: context.presentationID
        )
        guard SuperwallPlacement(rawValue: context.placement) != nil,
              let userID = telemetryOwner(for: context.presentationID)?.identity?.userID else {
            return
        }
        recordLifecyclePaywallDismissed(context.placement, context.dismissReason, userID)
    }

    func handleTransactionStarted(context: PaywallAnalyticsContext, productID: String) {
        guard let owner = telemetryOwner(for: context.presentationID) else { return }
        transactionContextStore.record(
            placement: context.placement,
            presentationID: context.presentationID,
            gateAttemptID: presentedToken.flatMap { token in
                token.presentationID == context.presentationID ? token.gateAttemptID : nil
            },
            recoveryPath: .hosted,
            identity: owner.identity,
            productID: productID
        )
        track(
            PaywallAnalyticsEvent.transactionStarted(
                context: context,
                productID: productID
            ),
            owner: owner
        )
    }

    func handleTransactionAbandoned(context: PaywallAnalyticsContext, productID: String) {
        track(
            PaywallAnalyticsEvent.transactionAbandoned(
                context: context,
                productID: productID
            ),
            presentationID: context.presentationID
        )
    }
}
