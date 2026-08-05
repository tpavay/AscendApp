import Foundation

/// The single network call behind the reconciliation recovery path.
@MainActor
protocol AppAccessReconciliationInvoking: AnyObject {
    func invokeReconciliation() async throws -> AppAccessReconciliationOutcome
}
