import Foundation
import os.lock

/// The StoreKit environment pair reported on every paywall, purchase, and restore event.
///
/// These are the two halves `EntitlementInfo.isActiveInCurrentEnvironment` compares, and neither
/// was observable anywhere in Ascend when that comparison refused a paying App Reviewer and cost
/// build 2026081401 a Guideline 2.1(b) rejection (#506). Diagnosing it took a second submission
/// only because no event carried either value.
///
/// They ride the analytics events rather than Crashlytics custom keys deliberately: the rejection
/// produced an alert, not a crash, so a custom key would have been attached to a report that never
/// existed. The keys are still set, for the crash and Sentry reports that do.
///
/// Diagnostic only - nothing routes, gates, or grants from either field. `holds_sandbox_entitlement`
/// is absent rather than `false` until RevenueCat has answered once, because "not asked yet" and
/// "bought in production" are different facts and only the second is evidence.
final class StoreKitEnvironmentDiagnostics: @unchecked Sendable {
    static let shared = StoreKitEnvironmentDiagnostics()

    private let sandboxEntitlement = OSAllocatedUnfairLock<Bool?>(initialState: nil)
    private let receiptName: @Sendable () -> String
    private let telemetry: TelemetryManager

    init(
        receiptName: @escaping @Sendable () -> String = { StoreKitReceiptEnvironment.receiptName },
        telemetry: TelemetryManager = .shared
    ) {
        self.receiptName = receiptName
        self.telemetry = telemetry
    }

    func record(holdsSandboxEntitlement: Bool) {
        sandboxEntitlement.withLock { $0 = holdsSandboxEntitlement }
        telemetry.set(.holdsSandboxEntitlement, value: holdsSandboxEntitlement)
        telemetry.set(.storeKitReceiptName, value: receiptName())
    }

    var parameters: [String: TelemetryValue] {
        var parameters: [String: TelemetryValue] = [
            "storekit_receipt_name": .string(receiptName())
        ]

        if let holdsSandboxEntitlement = sandboxEntitlement.withLock({ $0 }) {
            parameters["holds_sandbox_entitlement"] = .bool(holdsSandboxEntitlement)
        }

        return parameters
    }
}
