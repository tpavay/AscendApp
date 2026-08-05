import Foundation
@preconcurrency import FirebaseAuth

/// Owns when the device asks the server to re-derive paid access, and what counts as an answer.
@MainActor
final class AppAccessReconciliationService: AppAccessReconciling {
    static let shared = AppAccessReconciliationService()

    private static let answerSpacing: TimeInterval = 5 * 60
    private static let refusalSpacing: TimeInterval = 60
    private static let failureSpacing: TimeInterval = 30

    private let invoker: any AppAccessReconciliationInvoking
    private let currentUserID: @MainActor () -> String?
    private let clock: @Sendable () -> Date
    private let answerSpacing: TimeInterval
    private let refusalSpacing: TimeInterval
    private let failureSpacing: TimeInterval
    private var backoffUserID: String?
    private var nextAttemptAt: Date?
    private var inFlight: (requestID: UInt64, task: Task<Void, Never>)?
    private var lastRequestID: UInt64 = 0

    init(
        invoker: any AppAccessReconciliationInvoking = FunctionsAppAccessReconciliationInvoker(),
        currentUserID: @escaping @MainActor () -> String? = { Auth.auth().currentUser?.uid },
        clock: @escaping @Sendable () -> Date = Date.init,
        answerSpacing: TimeInterval = AppAccessReconciliationService.answerSpacing,
        refusalSpacing: TimeInterval = AppAccessReconciliationService.refusalSpacing,
        failureSpacing: TimeInterval = AppAccessReconciliationService.failureSpacing
    ) {
        self.invoker = invoker
        self.currentUserID = currentUserID
        self.clock = clock
        self.answerSpacing = answerSpacing
        self.refusalSpacing = refusalSpacing
        self.failureSpacing = failureSpacing
    }

    func reconcileAppAccess(force: Bool) async {
        guard let userID = currentUserID() else { return }

        if let inFlight {
            await inFlight.task.value
            if !force { return }
        }

        guard force || shouldReconcile(userID: userID) else { return }

        lastRequestID &+= 1
        let requestID = lastRequestID
        let task = Task { [weak self] () -> Void in
            await self?.performReconciliation(userID: userID)
        }
        inFlight = (requestID, task)
        await task.value
        // Only the request that installed the marker may clear it, or an overlapping caller's
        // marker is erased and a third caller starts a duplicate call it would have joined.
        if inFlight?.requestID == requestID {
            inFlight = nil
        }
    }

    private func shouldReconcile(userID: String) -> Bool {
        guard backoffUserID == userID, let nextAttemptAt else { return true }
        return clock() >= nextAttemptAt
    }

    /// Every outcome sets its own next-attempt time. Launch, foreground, identity change, the
    /// entitlement flip, purchase, and both restores all trigger this, so an outcome that records
    /// nothing would let a backgrounding user - or every subscriber during a RevenueCat outage -
    /// issue one call per trigger. A refusal or a failure still never counts as an answer.
    private func performReconciliation(userID: String) async {
        do {
            let outcome = try await invoker.invokeReconciliation()
            backOff(userID: userID, by: outcome.didDeriveAccess ? answerSpacing : refusalSpacing)
        } catch {
            backOff(userID: userID, by: failureSpacing)
            TelemetryManager.shared.recordError(
                error,
                context: .network,
                code: "app_access_reconciliation_failed"
            )
        }
    }

    private func backOff(userID: String, by spacing: TimeInterval) {
        backoffUserID = userID
        nextAttemptAt = clock().addingTimeInterval(spacing)
    }
}
