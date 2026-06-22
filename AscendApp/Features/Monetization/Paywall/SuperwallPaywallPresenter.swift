import Foundation
import os
import SuperwallKit

@MainActor
final class SuperwallPaywallPresenter: PaywallPresenting {
    static let shared = SuperwallPaywallPresenter()
    private static let logger = Logger(subsystem: "com.ascendapp.app", category: "Paywall")

    private(set) var isConfigured = false
    private let purchaseController = RevenueCatPurchaseController()

    func configure(configuration: MonetizationConfiguration = .live) {
        guard !isConfigured else { return }
        guard configuration.revenueCatAPIKey != nil else { return }
        guard let apiKey = configuration.superwallAPIKey else { return }

        let options = SuperwallOptions()
        options.testModeBehavior = configuration.isSuperwallTestModeEnabled ? .always : .never

        Superwall.configure(
            apiKey: apiKey,
            purchaseController: purchaseController,
            options: options
        )
        Superwall.shared.delegate = self
        purchaseController.syncSubscriptionStatus()
        isConfigured = true
    }

    func identify(userId: String) {
        guard isConfigured else { return }
        Superwall.shared.identify(userId: userId)
    }

    func resetIdentity() {
        guard isConfigured else { return }
        Superwall.shared.reset()
    }

    func register(placement: SuperwallPlacement, params: [String: Any]? = nil) {
        guard isConfigured else { return }
        let handler = makePresentationHandler(for: placement)

        Superwall.shared.register(
            placement: placement.rawValue,
            params: params,
            handler: handler,
            feature: {}
        )
    }

    private func makePresentationHandler(for placement: SuperwallPlacement) -> PaywallPresentationHandler {
        let handler = PaywallPresentationHandler()

        handler.onSkip { reason in
            Self.logger.warning("Superwall skipped placement \(placement.rawValue, privacy: .public): \(String(describing: reason), privacy: .public)")
            TelemetryManager.shared.track(
                TelemetryRecord(
                    name: "paywall_skipped",
                    parameters: [
                        "placement": .string(placement.rawValue),
                        "reason": .string(String(describing: reason))
                    ]
                )
            )
        }

        handler.onError { error in
            Self.logger.error("Superwall failed placement \(placement.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
            TelemetryManager.shared.track(
                TelemetryRecord(
                    name: "paywall_error",
                    parameters: [
                        "placement": .string(placement.rawValue),
                        "error": .string(String(describing: error))
                    ]
                )
            )
        }

        return handler
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
            TelemetryManager.shared.track(
                PaywallAnalyticsEvent.transactionStarted(
                    context: PaywallAnalyticsContext(paywallInfo: paywallInfo),
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
