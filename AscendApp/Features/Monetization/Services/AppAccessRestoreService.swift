import Foundation

enum AppAccessRestoreOutcome {
    case restored(entitlementIDs: Set<String>)
    /// The restore reached the store and conclusively found nothing to restore.
    case notFound
    /// The restore never resolved an entitlement answer, so it says nothing about what the
    /// climber owns.
    case failed(any Error)
}

enum AppAccessRestoreError: LocalizedError {
    case cancelled
    case offline
    case timedOut

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Restore was cancelled. Try Restore Purchases again."
        case .offline:
            return "Ascend is offline. Reconnect, then try Restore Purchases again."
        case .timedOut:
            return "Restore took too long. Check your connection, then try again."
        }
    }
}

/// The one restore every surface runs - the Superwall paywall's Restore button, the account
/// settings row, and the app-access gate.
///
/// Provider work is single-flight for one exact identity generation.
/// Each caller is still one observable attempt with one start and one terminal, because a caller
/// can independently time out or cancel without changing another surface's answer.
/// Keeping those events here prevents three surfaces from drifting into three different funnels.
@MainActor
final class AppAccessRestoreService {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    static let shared = AppAccessRestoreService()

    private let telemetry: TelemetryManager
    private let entitlementID: String
    private let restorer: @MainActor () -> any PurchaseRestoring
    private let timeout: Duration
    private let sleep: Sleep
    private struct Waiter {
        let continuation: CheckedContinuation<WaitResult, Never>
        let deadlineTask: Task<Void, Never>
    }
    private struct ProviderLane {
        let revision: UInt
        let identity: MonetizationIdentityTransition
        let task: Task<Void, Never>
        var waiters: [UUID: Waiter]
    }
    /// RevenueCat restore is callback-backed and does not cooperate with Swift cancellation.
    /// The lane therefore owns the provider task until its callback returns, while callers are
    /// represented only by removable continuations and cancellable deadline tasks.
    private var inFlightProvider: ProviderLane?
    private var lastProviderCompletion: (revision: UInt, outcome: AppAccessRestoreOutcome)?
    private var restoreRevision: UInt = 0

    init(
        telemetry: TelemetryManager = .shared,
        entitlementID: String = MonetizationConfiguration.live.revenueCatEntitlementID,
        restorer: @escaping @MainActor () -> any PurchaseRestoring = { MonetizationManager.shared },
        timeout: Duration = .seconds(15),
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.telemetry = telemetry
        self.entitlementID = entitlementID
        self.restorer = restorer
        self.timeout = timeout
        self.sleep = sleep
    }

    var isRestoreAvailable: Bool {
        restorer().isRevenueCatConfigured
    }

    var activeRestoreWaiterCount: Int {
        inFlightProvider?.waiters.count ?? 0
    }

    func restore(
        context: AppAccessRestoreAnalyticsContext = .accountSettings()
    ) async -> AppAccessRestoreOutcome {
        telemetry.track(PaywallAnalyticsEvent.revenueCatRestoreStarted(context: context))

        let restorer = self.restorer()
        guard restorer.isRevenueCatConfigured else {
            let outcome = AppAccessRestoreOutcome.failed(
                RevenueCatPurchaseControllerError.monetizationUnavailable
            )
            trackTerminal(
                outcome,
                context: context,
                identityMatches: false,
                errorType: .configuration
            )
            return outcome
        }
        guard let identity = restorer.identityGeneration else {
            let outcome = AppAccessRestoreOutcome.failed(
                RevenueCatPurchaseControllerError.entitlementUnconfirmed
            )
            trackTerminal(
                outcome,
                context: context,
                identityMatches: false,
                errorType: .entitlementUnresolved
            )
            return outcome
        }

        let outcome = await providerOutcome(for: identity, restorer: restorer)
        trackTerminal(
            outcome,
            context: context,
            identityMatches: restorer.identityGeneration == identity
        )
        return outcome
    }

    private func providerOutcome(
        for identity: MonetizationIdentityTransition,
        restorer: any PurchaseRestoring
    ) async -> AppAccessRestoreOutcome {
        while let current = inFlightProvider, current.identity != identity {
            // RevenueCat restore is process-global. A new account never runs concurrently with an
            // older account's provider call. It waits with its own deadline, then revalidates the
            // exact identity before it is allowed to start.
            switch await waitForProviderLane(revision: current.revision) {
            case .provider:
                guard restorer.identityGeneration == identity else {
                    return .failed(RevenueCatPurchaseControllerError.entitlementUnconfirmed)
                }
            case .timedOut:
                return .failed(AppAccessRestoreError.timedOut)
            case .cancelled:
                return .failed(AppAccessRestoreError.cancelled)
            }
        }

        guard restorer.identityGeneration == identity else {
            return .failed(RevenueCatPurchaseControllerError.entitlementUnconfirmed)
        }

        let revision: UInt
        if let current = inFlightProvider, current.identity == identity {
            revision = current.revision
        } else {
            restoreRevision &+= 1
            revision = restoreRevision
            let providerTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let outcome = await self.performRestore(with: restorer, identity: identity)
                self.completeProviderLane(revision: revision, outcome: outcome)
            }
            inFlightProvider = ProviderLane(
                revision: revision,
                identity: identity,
                task: providerTask,
                waiters: [:]
            )
        }

        switch await waitForProviderLane(revision: revision) {
        case .provider(let outcome):
            return outcome
        case .timedOut:
            return .failed(AppAccessRestoreError.timedOut)
        case .cancelled:
            return .failed(AppAccessRestoreError.cancelled)
        }
    }

    fileprivate enum WaitResult {
        case provider(AppAccessRestoreOutcome)
        case timedOut
        case cancelled
    }

    private func waitForProviderLane(revision: UInt) async -> WaitResult {
        if let completion = lastProviderCompletion, completion.revision == revision {
            return .provider(completion.outcome)
        }
        guard inFlightProvider?.revision == revision else {
            return .provider(.failed(RevenueCatPurchaseControllerError.entitlementUnconfirmed))
        }
        if Task.isCancelled { return .cancelled }

        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard var lane = inFlightProvider, lane.revision == revision else {
                    if let completion = lastProviderCompletion, completion.revision == revision {
                        continuation.resume(returning: .provider(completion.outcome))
                    } else {
                        continuation.resume(returning: .provider(
                            .failed(RevenueCatPurchaseControllerError.entitlementUnconfirmed)
                        ))
                    }
                    return
                }
                let deadlineTask = Task { @MainActor [weak self, sleep, timeout] in
                    do {
                        try await sleep(timeout)
                        self?.resolveWaiter(
                            waiterID,
                            revision: revision,
                            result: .timedOut
                        )
                    } catch {
                        // Provider completion or caller cancellation owns the terminal.
                    }
                }
                lane.waiters[waiterID] = Waiter(
                    continuation: continuation,
                    deadlineTask: deadlineTask
                )
                inFlightProvider = lane
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resolveWaiter(waiterID, revision: revision, result: .cancelled)
            }
        }
    }

    private func resolveWaiter(_ waiterID: UUID, revision: UInt, result: WaitResult) {
        guard var lane = inFlightProvider,
              lane.revision == revision,
              let waiter = lane.waiters.removeValue(forKey: waiterID) else { return }
        inFlightProvider = lane
        waiter.deadlineTask.cancel()
        waiter.continuation.resume(returning: result)
    }

    private func completeProviderLane(revision: UInt, outcome: AppAccessRestoreOutcome) {
        guard let lane = inFlightProvider, lane.revision == revision else { return }
        lastProviderCompletion = (revision, outcome)
        inFlightProvider = nil
        for waiter in lane.waiters.values {
            waiter.deadlineTask.cancel()
            waiter.continuation.resume(returning: .provider(outcome))
        }
    }

    private func performRestore(
        with restorer: any PurchaseRestoring,
        identity: MonetizationIdentityTransition
    ) async -> AppAccessRestoreOutcome {
        do {
            let restoredState = try await restorer.restorePurchases(for: identity)
            guard restorer.identityGeneration == identity else {
                return .failed(RevenueCatPurchaseControllerError.entitlementUnconfirmed)
            }

            switch restoredState {
            case .active(let entitlementIDs) where entitlementIDs.contains(entitlementID):
                return .restored(entitlementIDs: entitlementIDs)

            case .active, .inactive:
                return .notFound

            case .unknown:
                return .failed(RevenueCatPurchaseControllerError.entitlementUnconfirmed)
            }
        } catch {
            let errorType = RevenueCatAnalyticsErrorType(error: error)
            if errorType == .network {
                return .failed(AppAccessRestoreError.offline)
            }
            return .failed(error)
        }
    }

    private func trackTerminal(
        _ outcome: AppAccessRestoreOutcome,
        context: AppAccessRestoreAnalyticsContext,
        identityMatches: Bool,
        errorType explicitErrorType: RevenueCatAnalyticsErrorType? = nil
    ) {
        switch outcome {
        case .restored:
            telemetry.track(
                PaywallAnalyticsEvent.revenueCatRestoreCompleted(
                    entitlementID: entitlementID,
                    context: context,
                    identityMatches: identityMatches
                )
            )
        case .notFound:
            telemetry.track(
                PaywallAnalyticsEvent.revenueCatRestoreNotFound(
                    entitlementID: entitlementID,
                    context: context,
                    identityMatches: identityMatches
                )
            )
        case .failed(let error):
            let errorType = explicitErrorType ?? Self.analyticsErrorType(for: error)
            telemetry.track(
                PaywallAnalyticsEvent.revenueCatRestoreFailed(
                    entitlementID: entitlementID,
                    errorType: errorType,
                    context: context,
                    identityMatches: identityMatches
                )
            )
        }
    }

    private static func analyticsErrorType(for error: any Error) -> RevenueCatAnalyticsErrorType {
        switch error as? AppAccessRestoreError {
        case .cancelled:
            return .restoreCancelled
        case .offline:
            return .network
        case .timedOut:
            return .restoreTimedOut
        case nil:
            if let controllerError = error as? RevenueCatPurchaseControllerError,
               case .entitlementUnconfirmed = controllerError {
                return .entitlementUnresolved
            }
            return RevenueCatAnalyticsErrorType(error: error)
        }
    }
}
