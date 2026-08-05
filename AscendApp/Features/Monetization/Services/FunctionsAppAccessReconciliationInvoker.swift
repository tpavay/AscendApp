import Foundation
@preconcurrency import FirebaseFunctions

/// Calls the authenticated `reconcileAppAccess` callable.
///
/// It takes no arguments on purpose: entitlement state, product, expiry, and identity all come from
/// Firebase Authentication and RevenueCat's subscriber API on the server, never from the device.
@MainActor
final class FunctionsAppAccessReconciliationInvoker: AppAccessReconciliationInvoking {
    private static let callableName = "reconcileAppAccess"

    private let functions: Functions

    init(functions: Functions = Functions.functions(region: "us-central1")) {
        self.functions = functions
    }

    func invokeReconciliation() async throws -> AppAccessReconciliationOutcome {
        let result = try await functions.httpsCallable(Self.callableName).call()
        let payload = result.data as? [String: Any]
        return AppAccessReconciliationOutcome(status: payload?["status"] as? String)
    }
}
