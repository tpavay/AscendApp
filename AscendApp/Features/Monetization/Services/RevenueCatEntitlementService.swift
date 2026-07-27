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
            await auditLaunchOffering()
        }
    }

    func auditLaunchOffering() async {
        guard isConfigured else { return }
        guard let offerings = try? await Purchases.shared.offerings() else { return }

        let currentOffering = offerings.current
        let audit = configuration.auditOffering(
            identifier: currentOffering?.identifier,
            productIDs: Set(
                currentOffering?.availablePackages.map(\.storeProduct.productIdentifier) ?? []
            )
        )

        guard !audit.isValid else { return }

        Self.logger.error(
            "RevenueCat offering does not match the launch contract: \(audit.summary, privacy: .public)"
        )
        TelemetryManager.shared.track(
            TelemetryRecord(
                name: "monetization_offering_mismatch",
                parameters: audit.telemetryParameters,
                destinations: [.analytics, .crashlytics]
            )
        )
    }

    func refreshCustomerInfo() async {
        guard isConfigured else { return }

        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            apply(customerInfo: customerInfo)
        } catch {
            entitlementState = .unknown
        }
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
