import Foundation
import Testing
@testable import AscendApp

@MainActor
struct RestoreAnalyticsPrivacyContractTests {
    private static let commonFields: Set<String> = [
        "restore_attempt_id",
        "gate_attempt_id",
        "placement",
        "presentation_id",
        "restore_source",
        "recovery_path",
        "storekit_receipt_name",
        "holds_sandbox_entitlement"
    ]

    @Test
    func everyRestoreRecordStaysInsideTheDocumentedPrivacyAllowlist() throws {
        let context = AppAccessRestoreAnalyticsContext.hostedPaywall(
            placement: "app_access_gate",
            presentationID: "presentation-22",
            gateAttemptID: "gate-22"
        )
        let diagnostics = StoreKitEnvironmentDiagnostics(
            receiptName: { "sandboxReceipt" },
            telemetry: makeTestTelemetry(
                sink: InMemoryTelemetrySink(destination: .analytics)
            )
        )
        diagnostics.record(holdsSandboxEntitlement: true)

        let records = [
            PaywallAnalyticsEvent.revenueCatRestoreStarted(context: context)
                .record(diagnostics: diagnostics),
            PaywallAnalyticsEvent.revenueCatRestoreCompleted(
                entitlementID: "app_access",
                context: context,
                identityMatches: true
            ).record(diagnostics: diagnostics),
            PaywallAnalyticsEvent.revenueCatRestoreNotFound(
                entitlementID: "app_access",
                context: context,
                identityMatches: true
            ).record(diagnostics: diagnostics),
            PaywallAnalyticsEvent.revenueCatRestoreFailed(
                entitlementID: "app_access",
                errorType: .restoreTimedOut,
                context: context,
                identityMatches: false
            ).record(diagnostics: diagnostics)
        ]

        let terminalFields: Set<String> = [
            "outcome", "entitlement_id", "entitlement_active", "identity_match", "error_type"
        ]
        let allowedFields = Self.commonFields.union(terminalFields)
        for record in records {
            #expect(
                Set(record.parameters.keys).isSubset(of: allowedFields),
                "Undocumented restore analytics fields: \(Set(record.parameters.keys).subtracting(allowedFields))"
            )
            #expect(record.parameters["user_id"] == nil)
            #expect(record.parameters["identity_revision"] == nil)
            #expect(record.parameters["error"] == nil)
            #expect(record.parameters["receipt"] == nil)
            #expect(record.parameters["price"] == nil)
        }

        let documentationURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "PrivacyAnalyticsClassification.md")
        let documentation = try String(contentsOf: documentationURL, encoding: .utf8)
        for field in allowedFields {
            #expect(
                documentation.contains("`\(field)`"),
                "PrivacyAnalyticsClassification.md must classify \(field)"
            )
        }
    }

    @Test
    func restoreContextsAreBoundedAndNameTheirExactSurface() throws {
        let unsafeIdentifier = String(repeating: "a", count: 100) + " email@example.com"
        let gate = AppAccessRestoreAnalyticsContext.appAccessGate(
            gateAttemptID: unsafeIdentifier
        )
        let hosted = AppAccessRestoreAnalyticsContext.hostedPaywall(
            placement: "app_access_gate",
            presentationID: unsafeIdentifier,
            gateAttemptID: unsafeIdentifier
        )
        let account = AppAccessRestoreAnalyticsContext.accountSettings()

        #expect(gate.parameters["restore_source"] == .string("app_access_gate"))
        #expect(gate.parameters["recovery_path"] == .string("restore"))
        #expect(hosted.parameters["restore_source"] == .string("hosted_paywall"))
        #expect(hosted.parameters["recovery_path"] == .string("hosted"))
        #expect(account.parameters["restore_source"] == .string("account_settings"))
        #expect(account.parameters["recovery_path"] == .string("account"))

        for context in [gate, hosted, account] {
            guard case .string(let restoreAttemptID) = context.parameters["restore_attempt_id"] else {
                Issue.record("Missing restore attempt identifier")
                continue
            }
            #expect(restoreAttemptID.count <= 64)
        }
        for key in ["gate_attempt_id", "presentation_id"] {
            guard case .string(let value) = hosted.parameters[key] else {
                Issue.record("Missing bounded \(key)")
                continue
            }
            #expect(value.count == 64)
            #expect(value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
        }
    }
}
