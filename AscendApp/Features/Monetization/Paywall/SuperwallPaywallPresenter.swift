import Foundation
import os
import SuperwallKit

@MainActor
final class SuperwallPaywallPresenter: PaywallPresenting {
    static let shared = SuperwallPaywallPresenter()
    private static let logger = Logger(subsystem: "com.ascendapp.app", category: "Paywall")

    private(set) var isConfigured = false
    private let transactionContextStore = PaywallTransactionContextStore.shared
    private let purchaseController: RevenueCatPurchaseController
    private let attemptRegistry: SuperwallPresentationAttemptRegistry
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
    }
    private var registrations: [UInt: Registration] = [:]
    private var presentedToken: PresentedToken?
    private var presentationOperationTail: Task<Void, Never>?
    private var registrationTask: Task<Void, Never>?

    init(
        purchaseController: RevenueCatPurchaseController = RevenueCatPurchaseController(),
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
        }
    ) {
        self.purchaseController = purchaseController
        self.attemptRegistry = attemptRegistry
        isConfigured = startsConfigured
        self.registerPlacement = registerPlacement
        self.dismissPresentation = dismissPresentation
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
            let presentationID = PaywallAnalyticsContext(paywallInfo: paywallInfo).presentationID
            guard self.handlePresentationBegan(
                revision: revision,
                presentationID: presentationID
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
            let category = SuperwallSkipReasonCategory.classify(String(describing: reason))
            Self.logger.warning("Superwall skipped placement \(placement.rawValue, privacy: .public): \(category.rawValue, privacy: .public)")
            TelemetryManager.shared.track(
                PaywallAnalyticsEvent.diagnosticRecord(
                    name: "paywall_skipped",
                    parameters: [
                        "placement": .string(placement.rawValue),
                        "reason": .string(category.rawValue)
                    ]
                )
            )
            onOutcome(.skipped(reason: category.rawValue))
            self.registrations[revision] = nil
        }

        handler.onError { error in
            guard self.attemptRegistry.isAuthoritative(revision) else { return }
            Self.logger.error("Superwall failed placement \(placement.rawValue, privacy: .public)")
            TelemetryManager.shared.track(
                PaywallAnalyticsEvent.diagnosticRecord(
                    name: "paywall_error",
                    parameters: [
                        "placement": .string(placement.rawValue),
                        "error_type": .string("presentation_error")
                    ]
                )
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
                recoveryOwned: false
            )
        }
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
            gateAttemptID: token.gateAttemptID
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
            onOutcome(.dismissedWithoutPurchase)
        }
        presentedToken = nil
        registrations[revision] = nil
    }
}

extension SuperwallPaywallPresenter: HostedPurchaseRecoveryRouting {
    func recoverHostedPurchase(
        _ recovery: HostedPurchaseRecovery,
        context: RevenueCatPurchaseAnalyticsContext,
        identity: MonetizationIdentityTransition
    ) async -> Bool {
        guard let presentationID = context.presentationID else {
            trackRecoveryRefusal("missing_presentation_id")
            return false
        }
        guard var token = presentedToken,
              token.presentationID == presentationID,
              token.identity == identity,
              attemptRegistry.isAuthoritative(token.revision),
              !token.recoveryOwned else {
            trackRecoveryRefusal("stale_or_missing_token")
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

    private func trackRecoveryRefusal(_ reason: String) {
        TelemetryManager.shared.track(
            TelemetryRecord(
                name: "hosted_purchase_recovery_refused",
                parameters: ["reason": .string(reason)]
            )
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
        TelemetryManager.shared.track(
            PaywallAnalyticsEvent.shown(
                context: PaywallAnalyticsContext(paywallInfo: paywallInfo)
            )
        )

        recordLifecyclePaywallShownIfKnown(paywallInfo)
    }

    func didDismissPaywall(withInfo paywallInfo: PaywallInfo) {
        TelemetryManager.shared.track(
            PaywallAnalyticsEvent.dismissed(
                context: PaywallAnalyticsContext(paywallInfo: paywallInfo)
            )
        )

        recordLifecyclePaywallDismissedIfKnown(paywallInfo)
    }

    func handleSuperwallEvent(withInfo eventInfo: SuperwallEventInfo) {
        switch eventInfo.event {
        case .transactionStart(let product, let paywallInfo):
            let context = PaywallAnalyticsContext(paywallInfo: paywallInfo)
            transactionContextStore.record(
                placement: context.placement,
                presentationID: context.presentationID,
                gateAttemptID: presentedToken.flatMap { token in
                    token.presentationID == context.presentationID ? token.gateAttemptID : nil
                },
                recoveryPath: .hosted,
                productID: product.productIdentifier
            )
            TelemetryManager.shared.track(
                PaywallAnalyticsEvent.transactionStarted(
                    context: context,
                    productID: product.productIdentifier
                )
            )

        case .transactionComplete(_, let product, let transactionType, let paywallInfo):
            TelemetryManager.shared.track(
                PaywallAnalyticsEvent.transactionCompleted(
                    context: PaywallAnalyticsContext(paywallInfo: paywallInfo),
                    productID: product.productIdentifier,
                    transactionType: transactionType.description
                )
            )

        case .transactionFail(let error, let paywallInfo):
            TelemetryManager.shared.track(
                PaywallAnalyticsEvent.transactionFailed(
                    context: PaywallAnalyticsContext(paywallInfo: paywallInfo),
                    errorType: error.analyticsType,
                    productID: error.analyticsProductID
                )
            )

        case .transactionAbandon(let product, let paywallInfo):
            TelemetryManager.shared.track(
                PaywallAnalyticsEvent.transactionAbandoned(
                    context: PaywallAnalyticsContext(paywallInfo: paywallInfo),
                    productID: product.productIdentifier
                )
            )

        case .transactionRestore(let restoreType, let paywallInfo):
            TelemetryManager.shared.track(
                PaywallAnalyticsEvent.restoreCompleted(
                    context: PaywallAnalyticsContext(paywallInfo: paywallInfo),
                    restoreType: restoreType.analyticsType
                )
            )

        default:
            break
        }
    }

    private func recordLifecyclePaywallShownIfKnown(_ paywallInfo: PaywallInfo) {
        let placement = paywallInfo.analyticsPlacement
        guard SuperwallPlacement(rawValue: placement) != nil else { return }

        LifecycleEventRecorder.shared.recordPaywallShown(
            placement: placement
        )
    }

    private func recordLifecyclePaywallDismissedIfKnown(_ paywallInfo: PaywallInfo) {
        let placement = paywallInfo.analyticsPlacement
        guard SuperwallPlacement(rawValue: placement) != nil else { return }

        LifecycleEventRecorder.shared.recordPaywallDismissed(
            placement: placement,
            reason: String(describing: paywallInfo.closeReason)
        )
    }
}
