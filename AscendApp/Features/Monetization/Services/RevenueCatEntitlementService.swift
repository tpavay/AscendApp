import Foundation
import Observation
import os
import RevenueCat

@MainActor
@Observable
final class RevenueCatEntitlementService: EntitlementServicing {
    static let shared = RevenueCatEntitlementService()
    private static let logger = Logger(subsystem: "com.ascendapp.app", category: "Monetization")

    var entitlementState: MonetizationEntitlementState {
        identityTransitionState.entitlementState
    }
    var hasFailedIdentityResolution: Bool {
        identityTransitionState.hasFailedIdentityResolution
    }
    var identityGeneration: MonetizationIdentityTransition? {
        identityTransitionState.refreshToken()
    }
    private(set) var isConfigured: Bool
    var scheduledIdentityMutationCount: Int {
        identityMutationTasks.count
    }

    private let provider: any RevenueCatEntitlementProviding
    private var configuration = MonetizationConfiguration.live
    private var customerInfoTask: Task<Void, Never>?
    private var didCompleteLaunchOfferingAudit = false
    private var identityMutationTail: Task<Void, Never>?
    private var identityMutationTasks: [
        MonetizationIdentityTransition: Task<Void, Never>
    ] = [:]
    private var identityTransitionState = MonetizationIdentityTransitionState()
    private var pendingIdentityMutation: (
        transition: MonetizationIdentityTransition,
        mutation: RevenueCatIdentityMutation
    )?

    init(
        provider: any RevenueCatEntitlementProviding = RevenueCatPurchasesProvider(),
        startsConfigured: Bool = false
    ) {
        self.provider = provider
        isConfigured = startsConfigured
    }

    func configure(configuration: MonetizationConfiguration = .live) {
        guard !isConfigured else { return }

        self.configuration = configuration

        guard let apiKey = configuration.revenueCatAPIKey else {
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
        Task {
            await auditLaunchOfferingIfNeeded()
        }

        if identityTransitionState.refreshToken() != nil {
            observeCustomerInfoUpdates()
            Task {
                await refreshCustomerInfo()
            }
        }
    }

    @discardableResult
    func refreshCustomerInfo(
        waitsForPendingIdentity: Bool
    ) async -> MonetizationEntitlementRefresh {
        guard isConfigured else {
            return .unavailable(.notConfigured)
        }

        if let pendingIdentityMutation {
            // A background pass has nothing to decide from a transitional answer, so it neither
            // waits for identity work nor re-drives it - `retryIdentityResolution` owns that, and
            // its caller can show recovery instead of stalling a launch or foreground chain.
            guard waitsForPendingIdentity else {
                return .unavailable(.identityUnresolved)
            }

            let transition = pendingIdentityMutation.transition
            let identityWork = identityMutationTasks[transition] ?? scheduleIdentityMutation(
                transition: transition,
                mutation: pendingIdentityMutation.mutation
            )

            await identityWork.value
        }

        guard let refreshToken = identityTransitionState.refreshToken() else {
            return .unavailable(.identityUnresolved)
        }

        do {
            let state = try await provider.customerInfoState()

            // The identity can move on while that call is suspended. An answer the transition state
            // refuses describes a superseded identity, so reporting it as refreshed would put the
            // verdict and the entitlement this app actually holds back into disagreement.
            guard applyRefreshState(state, for: refreshToken) else {
                return .unavailable(.identityUnresolved)
            }

            // Nothing may suspend between accepting the state and reporting it, or the identity
            // could move on again and reopen the window that guard just closed. The catalog audit
            // is unrelated to this verdict, so it runs on its own rather than inside it.
            Task { await auditLaunchOfferingIfNeeded() }
            return .refreshed(state)
        } catch {
            // A refresh that could not reach RevenueCat is not evidence that the entitlement
            // lapsed, so the already-resolved answer stands until something can ask again - but the
            // caller is told nothing current was established rather than reading that stale answer.
            Self.logger.error(
                "Could not refresh RevenueCat customer info: \(error.localizedDescription, privacy: .public)"
            )
            return .unavailable(.providerFailed)
        }
    }

    private func auditLaunchOfferingIfNeeded() async {
        guard !didCompleteLaunchOfferingAudit,
              configuration.shouldAuditLaunchOffering else {
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

    func prepareIdentity(
        _ customer: MonetizationCustomerIdentity
    ) -> MonetizationIdentityTransition {
        prepareIdentityMutation(
            userID: customer.userID,
            mutation: .identify(customer)
        )
    }

    func identify(
        _ customer: MonetizationCustomerIdentity,
        transition: MonetizationIdentityTransition
    ) async {
        guard transition.userID == customer.userID else { return }
        await identityMutationTasks[transition]?.value
    }

    func prepareIdentityReset() -> MonetizationIdentityTransition {
        prepareIdentityMutation(userID: nil, mutation: .reset)
    }

    func resetIdentity(transition: MonetizationIdentityTransition) async {
        guard transition.userID == nil else { return }
        await identityMutationTasks[transition]?.value
    }

    /// Runs the still-unanswered identity mutation again. Caller-driven only - nothing schedules
    /// this - so a provider outage surfaces as a recoverable screen rather than a stuck spinner.
    func retryIdentityResolution() async {
        guard identityTransitionState.hasFailedIdentityResolution,
              let pendingIdentityMutation else {
            return
        }

        let transition = pendingIdentityMutation.transition
        guard identityMutationTasks[transition] == nil else { return }

        let mutationTask = scheduleIdentityMutation(
            transition: transition,
            mutation: pendingIdentityMutation.mutation
        )
        await mutationTask.value
    }

    /// A pending or superseded identity transition refuses the stored state, but it does not make
    /// the restore's own answer wrong. The resolved state is returned either way so a caller that
    /// asked for the restore can act on what RevenueCat actually said.
    @discardableResult
    func restorePurchases() async throws -> MonetizationEntitlementState {
        guard isConfigured else { return .unknown }
        let refreshToken = identityTransitionState.refreshToken()
        let state = try await provider.restorePurchasesState()

        if let refreshToken {
            applyRefreshState(state, for: refreshToken)
        }

        return state
    }

    private func prepareIdentityMutation(
        userID: String?,
        mutation: RevenueCatIdentityMutation
    ) -> MonetizationIdentityTransition {
        customerInfoTask?.cancel()
        customerInfoTask = nil

        let transition = identityTransitionState.prepare(userID: userID)
        pendingIdentityMutation = (transition, mutation)
        _ = scheduleIdentityMutation(transition: transition, mutation: mutation)
        return transition
    }

    private func scheduleIdentityMutation(
        transition: MonetizationIdentityTransition,
        mutation: RevenueCatIdentityMutation
    ) -> Task<Void, Never> {
        let priorMutation = identityMutationTail
        let mutationTask = Task { @MainActor [weak self] in
            await priorMutation?.value

            guard let self else {
                return
            }
            defer {
                self.identityMutationTasks[transition] = nil
            }

            guard self.identityTransitionState.isPending(transition) else {
                return
            }

            let state = await self.performIdentityMutation(mutation)
            self.finishIdentityMutation(state, for: transition)
        }

        identityMutationTasks[transition] = mutationTask
        identityMutationTail = Task { @MainActor in
            await mutationTask.value
        }
        return mutationTask
    }

    private func performIdentityMutation(
        _ mutation: RevenueCatIdentityMutation
    ) async -> MonetizationEntitlementState {
        guard isConfigured else {
            return .inactive
        }

        do {
            switch mutation {
            case .identify(let customer):
                let state = try await provider.logInState(userID: customer.userID)

                // Only ever after the log-in settles, and only ever from inside this serialized
                // mutation: the attribute lands on whichever app user RevenueCat currently holds,
                // and `identityMutationTail` is what guarantees that is still `customer`. Nothing
                // is written when the app knows no address - see `setCustomerEmail`.
                if let email = customer.email {
                    provider.setCustomerEmail(email)
                }

                return state
            case .reset:
                // Signing out leaves the departing climber's email on the departing climber's own
                // customer, which is the record the captain needs to keep. RevenueCat's log-out
                // moves the app onto a fresh anonymous customer that never carried an address, so
                // there is nothing stale here to clear.
                return try await provider.logOutState()
            }
        } catch {
            return .unknown
        }
    }

    private func finishIdentityMutation(
        _ state: MonetizationEntitlementState,
        for transition: MonetizationIdentityTransition
    ) {
        guard identityTransitionState.resolve(state, for: transition) else {
            return
        }

        guard state != .unknown else {
            return
        }

        if pendingIdentityMutation?.transition == transition {
            pendingIdentityMutation = nil
        }
        updateTelemetry(for: state)
        observeCustomerInfoUpdates()
    }

    private func observeCustomerInfoUpdates() {
        guard isConfigured else {
            return
        }

        customerInfoTask?.cancel()
        customerInfoTask = Task { @MainActor [weak self, provider] in
            for await state in provider.customerInfoUpdates {
                guard !Task.isCancelled, let self else { return }
                self.applyStreamedState(state)
            }
        }
    }

    /// The stream already carries the answer, so applying it directly keeps the entitlement current
    /// without a second round trip that could itself fail.
    private func applyStreamedState(_ state: MonetizationEntitlementState) {
        guard let refreshToken = identityTransitionState.refreshToken() else {
            return
        }

        applyRefreshState(state, for: refreshToken)
    }

    @discardableResult
    private func applyRefreshState(
        _ state: MonetizationEntitlementState,
        for refreshToken: MonetizationIdentityTransition
    ) -> Bool {
        guard identityTransitionState.applyRefresh(state, for: refreshToken) else {
            return false
        }

        updateTelemetry(for: state)
        return true
    }

    private func updateTelemetry(for state: MonetizationEntitlementState) {
        TelemetryManager.shared.set(
            .hasAppAccess,
            value: state.hasActiveEntitlement(configuration.revenueCatEntitlementID)
        )
    }
}
