import Foundation
import Observation
import RevenueCat

@MainActor
@Observable
final class RevenueCatEntitlementService: EntitlementServicing {
    static let shared = RevenueCatEntitlementService()

    var entitlementState: MonetizationEntitlementState {
        identityTransitionState.entitlementState
    }
    private(set) var isConfigured = false

    private var configuration = MonetizationConfiguration.live
    private var customerInfoTask: Task<Void, Never>?
    private var identityTransitionState = MonetizationIdentityTransitionState()

    func configure(configuration: MonetizationConfiguration = .live) {
        guard !isConfigured else { return }

        self.configuration = configuration

        guard let apiKey = configuration.revenueCatAPIKey else {
            applyCurrentState(.inactive)
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
        let identitySnapshot = identityTransitionState.snapshot()

        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            apply(
                customerInfo: customerInfo,
                forRefreshOf: identitySnapshot
            )
        } catch {
            applyRefreshState(.unknown, for: identitySnapshot)
        }
    }

    func prepareIdentity(userId: String) -> MonetizationIdentityTransition {
        identityTransitionState.prepare(userID: userId)
    }

    func identify(
        userId: String,
        transition: MonetizationIdentityTransition
    ) async {
        guard isConfigured else {
            resolve(.inactive, for: transition)
            return
        }

        do {
            let logInResult = try await Purchases.shared.logIn(userId)
            resolve(
                entitlementState(from: logInResult.customerInfo),
                for: transition
            )
        } catch {
            resolve(.unknown, for: transition)
        }
    }

    func prepareIdentityReset() -> MonetizationIdentityTransition {
        identityTransitionState.prepare(userID: nil)
    }

    func resetIdentity(transition: MonetizationIdentityTransition) async {
        guard isConfigured else {
            resolve(.inactive, for: transition)
            return
        }

        do {
            let customerInfo = try await Purchases.shared.logOut()
            resolve(
                entitlementState(from: customerInfo),
                for: transition
            )
        } catch {
            resolve(.unknown, for: transition)
        }
    }

    func restorePurchases() async throws {
        guard isConfigured else { return }
        let identitySnapshot = identityTransitionState.snapshot()

        let customerInfo = try await Purchases.shared.restorePurchases()
        apply(
            customerInfo: customerInfo,
            forRefreshOf: identitySnapshot
        )
    }

    private func observeCustomerInfo() {
        customerInfoTask?.cancel()
        customerInfoTask = Task { [weak self] in
            for await customerInfo in Purchases.shared.customerInfoStream {
                self?.applyCurrent(customerInfo: customerInfo)
            }
        }
    }

    private func applyCurrent(customerInfo: CustomerInfo) {
        let snapshot = identityTransitionState.snapshot()
        apply(customerInfo: customerInfo, forRefreshOf: snapshot)
    }

    private func apply(
        customerInfo: CustomerInfo,
        forRefreshOf snapshot: MonetizationIdentityTransition
    ) {
        applyRefreshState(
            entitlementState(from: customerInfo),
            for: snapshot
        )
    }

    private func entitlementState(from customerInfo: CustomerInfo) -> MonetizationEntitlementState {
        let activeEntitlementIDs = Set(customerInfo.entitlements.activeInCurrentEnvironment.keys)

        return activeEntitlementIDs.isEmpty
            ? .inactive
            : .active(activeEntitlementIDs)
    }

    private func resolve(
        _ state: MonetizationEntitlementState,
        for transition: MonetizationIdentityTransition
    ) {
        guard identityTransitionState.resolve(state, for: transition) else {
            return
        }

        updateTelemetry(for: state)
    }

    private func applyRefreshState(
        _ state: MonetizationEntitlementState,
        for snapshot: MonetizationIdentityTransition
    ) {
        guard identityTransitionState.applyRefresh(state, for: snapshot) else {
            return
        }

        updateTelemetry(for: state)
    }

    private func applyCurrentState(_ state: MonetizationEntitlementState) {
        let snapshot = identityTransitionState.snapshot()
        guard identityTransitionState.applyRefresh(state, for: snapshot) else {
            return
        }

        updateTelemetry(for: state)
    }

    private func updateTelemetry(for state: MonetizationEntitlementState) {
        TelemetryManager.shared.set(
            .hasAppAccess,
            value: state.hasActiveEntitlement(configuration.revenueCatEntitlementID)
        )
    }
}
