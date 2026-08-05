import Foundation
@preconcurrency import FirebaseAuth

/// Owns when the device asks the server to re-derive paid access, and what counts as an answer.
@MainActor
final class AppAccessReconciliationService: AppAccessReconciling {
    static let shared = AppAccessReconciliationService()

    private static let minimumSpacing: TimeInterval = 5 * 60

    private let invoker: any AppAccessReconciliationInvoking
    private let currentUserID: @MainActor () -> String?
    private let clock: @Sendable () -> Date
    private let minimumSpacing: TimeInterval
    private var lastSucceededUserID: String?
    private var lastSucceededAt: Date?
    private var inFlight: (requestID: UInt64, task: Task<Void, Never>)?
    private var lastRequestID: UInt64 = 0

    init(
        invoker: any AppAccessReconciliationInvoking = FunctionsAppAccessReconciliationInvoker(),
        currentUserID: @escaping @MainActor () -> String? = { Auth.auth().currentUser?.uid },
        clock: @escaping @Sendable () -> Date = Date.init,
        minimumSpacing: TimeInterval = AppAccessReconciliationService.minimumSpacing
    ) {
        self.invoker = invoker
        self.currentUserID = currentUserID
        self.clock = clock
        self.minimumSpacing = minimumSpacing
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
        guard lastSucceededUserID == userID, let lastSucceededAt else { return true }
        return clock().timeIntervalSince(lastSucceededAt) >= minimumSpacing
    }

    private func performReconciliation(userID: String) async {
        do {
            // A throttled refusal is not an answer, so it never satisfies the spacing below and the
            // next refresh, foreground, or restore asks again.
            guard try await invoker.invokeReconciliation().didDeriveAccess else { return }
            lastSucceededUserID = userID
            lastSucceededAt = clock()
        } catch {
            // A reconciliation that could not reach the server is not evidence of anything, so the
            // next refresh, foreground, or restore retries it rather than recording a success.
            TelemetryManager.shared.recordError(
                error,
                context: .network,
                code: "app_access_reconciliation_failed"
            )
        }
    }
}
