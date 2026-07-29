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
    private(set) var isConfigured: Bool
    var scheduledIdentityMutationCount: Int {
        identityMutationTasks.count
    }

    private let provider: any RevenueCatEntitlementProviding
    private var configuration = MonetizationConfiguration.live
    private var customerInfoTask: Task<Void, Never>?
    private var identityMutationTail: Task<Void, Never>?
    private var identityMutationTasks: [
        MonetizationIdentityTransition: Task<Void, Never>
    ] = [:]
    private var identityTransitionState = MonetizationIdentityTransitionState()

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

        if identityTransitionState.refreshToken() != nil {
            observeCustomerInfoUpdates()
            Task {
                await refreshCustomerInfo()
            }
        }
    }

    func refreshCustomerInfo() async {
        guard isConfigured,
              let refreshToken = identityTransitionState.refreshToken() else {
            return
        }

        do {
            let state = try await provider.customerInfoState()
            applyRefreshState(state, for: refreshToken)
        } catch {
            applyRefreshState(.unknown, for: refreshToken)
        }
    }

    func prepareIdentity(userId: String) -> MonetizationIdentityTransition {
        prepareIdentityMutation(
            userID: userId,
            mutation: .identify(userID: userId)
        )
    }

    func identify(
        userId: String,
        transition: MonetizationIdentityTransition
    ) async {
        guard transition.userID == userId else { return }
        await identityMutationTasks[transition]?.value
    }

    func prepareIdentityReset() -> MonetizationIdentityTransition {
        prepareIdentityMutation(userID: nil, mutation: .reset)
    }

    func resetIdentity(transition: MonetizationIdentityTransition) async {
        guard transition.userID == nil else { return }
        await identityMutationTasks[transition]?.value
    }

    func restorePurchases() async throws {
        guard isConfigured else { return }
        let refreshToken = identityTransitionState.refreshToken()
        let state = try await provider.restorePurchasesState()

        if let refreshToken {
            applyRefreshState(state, for: refreshToken)
        }
    }

    private func prepareIdentityMutation(
        userID: String?,
        mutation: RevenueCatIdentityMutation
    ) -> MonetizationIdentityTransition {
        customerInfoTask?.cancel()
        customerInfoTask = nil

        let transition = identityTransitionState.prepare(userID: userID)
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
        return transition
    }

    private func performIdentityMutation(
        _ mutation: RevenueCatIdentityMutation
    ) async -> MonetizationEntitlementState {
        guard isConfigured else {
            return .inactive
        }

        do {
            switch mutation {
            case .identify(let userID):
                return try await provider.logInState(userID: userID)
            case .reset:
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

        updateTelemetry(for: state)
        observeCustomerInfoUpdates()
    }

    private func observeCustomerInfoUpdates() {
        customerInfoTask?.cancel()
        customerInfoTask = Task { @MainActor [weak self, provider] in
            for await _ in provider.customerInfoUpdates {
                guard !Task.isCancelled else { return }
                await self?.refreshCustomerInfo()
            }
        }
    }

    private func applyRefreshState(
        _ state: MonetizationEntitlementState,
        for refreshToken: MonetizationIdentityTransition
    ) {
        guard identityTransitionState.applyRefresh(state, for: refreshToken) else {
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
