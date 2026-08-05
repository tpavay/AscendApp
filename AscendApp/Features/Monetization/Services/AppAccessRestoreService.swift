import Foundation

enum AppAccessRestoreOutcome {
    case restored(entitlementIDs: Set<String>)
    /// The restore reached the store and conclusively found nothing to restore.
    case notFound
    /// The restore never resolved an entitlement answer, so it says nothing about what the
    /// climber owns.
    case failed(any Error)
}

/// The one restore every surface runs - the Superwall paywall's Restore button, the account
/// settings row, and the app-access gate.
///
/// Restore is one operation and produces one terminal, so the started event and the single
/// `revenuecat_restore_completed` / `_not_found` / `_failed` terminal live here rather than in each
/// caller, where three copies of the contract would drift into three different funnels.
@MainActor
struct AppAccessRestoreService {
    private let telemetry: TelemetryManager
    private let entitlementID: String
    private let restorer: @MainActor () -> any PurchaseRestoring

    init(
        telemetry: TelemetryManager = .shared,
        entitlementID: String = MonetizationConfiguration.live.revenueCatEntitlementID,
        restorer: @escaping @MainActor () -> any PurchaseRestoring = { MonetizationManager.shared }
    ) {
        self.telemetry = telemetry
        self.entitlementID = entitlementID
        self.restorer = restorer
    }

    var isRestoreAvailable: Bool {
        restorer().isRevenueCatConfigured
    }

    func restore() async -> AppAccessRestoreOutcome {
        let restorer = self.restorer()

        // No RevenueCat call happens on an unconfigured build, so there is no start to report -
        // only the terminal that says why the operation could not run.
        guard restorer.isRevenueCatConfigured else {
            telemetry.track(
                PaywallAnalyticsEvent.revenueCatRestoreFailed(
                    entitlementID: entitlementID,
                    errorType: .configuration
                )
            )
            return .failed(RevenueCatPurchaseControllerError.monetizationUnavailable)
        }

        telemetry.track(PaywallAnalyticsEvent.revenueCatRestoreStarted)

        do {
            // The restore publishes what RevenueCat resolved for *this* call rather than the stored
            // `entitlementState`, which a pending identity transition can hold at `.unknown`.
            switch try await restorer.restorePurchases() {
            case .active(let entitlementIDs) where entitlementIDs.contains(entitlementID):
                telemetry.track(
                    PaywallAnalyticsEvent.revenueCatRestoreCompleted(entitlementID: entitlementID)
                )
                return .restored(entitlementIDs: entitlementIDs)

            case .active, .inactive:
                telemetry.track(
                    PaywallAnalyticsEvent.revenueCatRestoreNotFound(entitlementID: entitlementID)
                )
                return .notFound

            case .unknown:
                telemetry.track(
                    PaywallAnalyticsEvent.revenueCatRestoreFailed(
                        entitlementID: entitlementID,
                        errorType: .entitlementUnresolved
                    )
                )
                return .failed(RevenueCatPurchaseControllerError.entitlementUnconfirmed)
            }
        } catch {
            telemetry.track(
                PaywallAnalyticsEvent.revenueCatRestoreFailed(
                    entitlementID: entitlementID,
                    errorType: RevenueCatAnalyticsErrorType(error: error)
                )
            )
            return .failed(error)
        }
    }
}
