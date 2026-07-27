import Foundation
import Observation
import os
import RevenueCat

@MainActor
@Observable
final class RevenueCatEntitlementService: EntitlementServicing {
    static let shared = RevenueCatEntitlementService()
    private static let logger = Logger(subsystem: "com.ascendapp.app", category: "Monetization")

    private(set) var entitlementState: MonetizationEntitlementState = .unknown
    private(set) var isConfigured = false

    private var configuration = MonetizationConfiguration.live
    private var customerInfoTask: Task<Void, Never>?
    private var didCompleteLaunchOfferingAudit = false

    func configure(configuration: MonetizationConfiguration = .live) {
        guard !isConfigured else { return }

        self.configuration = configuration

        guard let apiKey = configuration.revenueCatAPIKey else {
            entitlementState = .inactive
            TelemetryManager.shared.set(.hasAppAccess, value: false)
            return
        }

        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif

        if !Purchases.isConfigured {
            Purchases.configure(withAPIKey: apiKey)
        }

        isConfigured = true
        observeCustomerInfo()

        Task {
            await refreshCustomerInfo()
        }
    }

    func refreshCustomerInfo() async {
        guard isConfigured else { return }

        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            apply(customerInfo: customerInfo)
            await auditLaunchOfferingIfNeeded()
        } catch {
            entitlementState = .unknown
        }
    }

    private func auditLaunchOfferingIfNeeded() async {
        guard !didCompleteLaunchOfferingAudit,
              configuration.revenueCatStoreMode == .appStore else {
            return
        }

        let offerings: Offerings
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            Self.logger.error(
                "Could not load RevenueCat offerings for the launch audit: \(error.localizedDescription, privacy: .public)"
            )
            return
        }

        didCompleteLaunchOfferingAudit = true

        let expectedOffering = offerings.all[configuration.revenueCatOfferingID]
        let audit = configuration.auditOffering(
            expectedOfferingProductIDs: expectedOffering.map { offering in
                Set(offering.availablePackages.map(\.storeProduct.productIdentifier))
            },
            currentOfferingID: offerings.current?.identifier
        )

        if !audit.isServingExpectedOffering {
            Self.logger.debug(
                "RevenueCat is serving offering \(audit.currentOfferingID ?? "none", privacy: .public) instead of \(audit.expectedOfferingID, privacy: .public)"
            )
        }

        guard !audit.isLaunchCatalogComplete else { return }

        Self.logger.error(
            "RevenueCat is missing the launch catalog: \(audit.summary, privacy: .public)"
        )
        TelemetryManager.shared.track(
            TelemetryRecord(
                name: "monetization_offering_mismatch",
                parameters: audit.telemetryParameters,
                destinations: [.analytics, .crashlytics]
            )
        )
    }

    func identify(userId: String) async {
        guard isConfigured else { return }

        do {
            let logInResult = try await Purchases.shared.logIn(userId)
            apply(customerInfo: logInResult.customerInfo)
        } catch {
            entitlementState = .unknown
        }
    }

    func resetIdentity() async {
        guard isConfigured else {
            entitlementState = .inactive
            TelemetryManager.shared.set(.hasAppAccess, value: false)
            return
        }

        do {
            let customerInfo = try await Purchases.shared.logOut()
            apply(customerInfo: customerInfo)
        } catch {
            entitlementState = .inactive
            TelemetryManager.shared.set(.hasAppAccess, value: false)
        }
    }

    func restorePurchases() async throws {
        guard isConfigured else { return }

        let customerInfo = try await Purchases.shared.restorePurchases()
        apply(customerInfo: customerInfo)
    }

    private func observeCustomerInfo() {
        customerInfoTask?.cancel()
        customerInfoTask = Task { [weak self] in
            for await customerInfo in Purchases.shared.customerInfoStream {
                self?.apply(customerInfo: customerInfo)
            }
        }
    }

    private func apply(customerInfo: CustomerInfo) {
        let activeEntitlementIDs = Set(customerInfo.entitlements.activeInCurrentEnvironment.keys)

        if activeEntitlementIDs.isEmpty {
            entitlementState = .inactive
        } else {
            entitlementState = .active(activeEntitlementIDs)
        }

        TelemetryManager.shared.set(
            .hasAppAccess,
            value: activeEntitlementIDs.contains(configuration.revenueCatEntitlementID)
        )
    }
}
