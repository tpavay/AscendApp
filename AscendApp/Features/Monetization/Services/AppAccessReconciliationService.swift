import Foundation
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFunctions

/// Invokes the authenticated `reconcileAppAccess` callable.
///
/// The callable takes no arguments on purpose: entitlement state, product, expiry, and identity all
/// come from Firebase Authentication and RevenueCat's subscriber API on the server, never from here.
@MainActor
final class AppAccessReconciliationService: AppAccessReconciling {
    static let shared = AppAccessReconciliationService()

    private static let callableName = "reconcileAppAccess"
    private static let minimumSpacing: TimeInterval = 5 * 60

    private let functions: Functions
    private let currentUserID: @MainActor () -> String?
    private let clock: @Sendable () -> Date
    private let minimumSpacing: TimeInterval
    private var lastSucceededUserID: String?
    private var lastSucceededAt: Date?
    private var inFlight: Task<Void, Never>?

    init(
        functions: Functions = Functions.functions(region: "us-central1"),
        currentUserID: @escaping @MainActor () -> String? = { Auth.auth().currentUser?.uid },
        clock: @escaping @Sendable () -> Date = Date.init,
        minimumSpacing: TimeInterval = AppAccessReconciliationService.minimumSpacing
    ) {
        self.functions = functions
        self.currentUserID = currentUserID
        self.clock = clock
        self.minimumSpacing = minimumSpacing
    }

    func reconcileAppAccess(force: Bool) async {
        guard let userID = currentUserID() else { return }

        if let inFlight {
            await inFlight.value
            if !force { return }
        }

        guard force || shouldReconcile(userID: userID) else { return }

        let task = Task { [weak self] () -> Void in
            await self?.performReconciliation(userID: userID)
        }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func shouldReconcile(userID: String) -> Bool {
        guard lastSucceededUserID == userID, let lastSucceededAt else { return true }
        return clock().timeIntervalSince(lastSucceededAt) >= minimumSpacing
    }

    private func performReconciliation(userID: String) async {
        do {
            _ = try await functions.httpsCallable(Self.callableName).call()
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
