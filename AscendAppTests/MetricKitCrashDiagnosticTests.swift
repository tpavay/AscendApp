import Foundation
import Testing
@testable import AscendApp

/// The crash channel a full phone cannot silence: an `MXCrashDiagnostic` reduced to the facts
/// Ascend records, reported once however often MetricKit hands it over.
struct MetricKitCrashDiagnosticTests {
    /// The LevelDB commit assertion as iOS 17+ reports it through
    /// `MXCrashDiagnosticObjectiveCExceptionReason`: the one string neither in-process crash
    /// reporter nor Sentry's own MetricKit conversion delivered on 2026-10-23.
    private static let levelDBAssertion = AppCrashDiagnosticSummary.ExceptionReason(
        exceptionName: "FIRESTORE INTERNAL ASSERTION FAILED",
        className: "NSException",
        composedMessage: "FIRESTORE INTERNAL ASSERTION FAILED: Failed to commit transaction:\n"
            + "Locally write mutations: IO error: /var/mobile/Containers/Data/Application/"
            + "4D1B/Library/Application Support/firestore/__FIRAPP_DEFAULT/ascend-prod-9c8f2/main/"
            + "000157.log: No space left on device (expected created.ok())"
    )

    private func summary(
        exceptionReason: AppCrashDiagnosticSummary.ExceptionReason? = levelDBAssertion,
        signal: Int? = 6,
        terminationReason: String? = "Namespace SIGNAL, Code 6 Abort trap: 6",
        callStackDigest: String = "a3f1"
    ) -> AppCrashDiagnosticSummary {
        AppCrashDiagnosticSummary(
            appBuildVersion: "1.2.3",
            osVersion: "iPhone OS 26.0.1 (23A355)",
            deviceType: "iPhone16,1",
            periodStart: Date(timeIntervalSince1970: 1_792_713_600),
            periodEnd: Date(timeIntervalSince1970: 1_792_800_000),
            exceptionType: 10,
            exceptionCode: 0,
            signal: signal,
            terminationReason: terminationReason,
            hasVirtualMemoryRegionInfo: false,
            exceptionReason: exceptionReason,
            callStackDigest: callStackDigest
        )
    }

    private func ledger(capacity: Int = CrashDiagnosticReportLedger.defaultCapacity) -> CrashDiagnosticReportLedger {
        CrashDiagnosticReportLedger(
            userDefaults: UserDefaults(suiteName: "crash-ledger-\(UUID().uuidString)")!,
            capacity: capacity
        )
    }

    @Test("A crash diagnostic becomes one app_crash_diagnostic event carrying the assertion text, the signal and the build")
    func recordCarriesTheReason() {
        let record = summary().record
        #expect(record.name == "app_crash_diagnostic")
        #expect(record.parameters["exception_name"] == .string("FIRESTORE INTERNAL ASSERTION FAILED"))
        #expect(record.parameters["exception_class"] == .string("NSException"))
        #expect(record.parameters["has_exception_reason"] == .bool(true))
        #expect(record.parameters["signal"] == .int(6))
        #expect(record.parameters["exception_type"] == .int(10))
        #expect(record.parameters["termination_reason"] == .string("Namespace SIGNAL, Code 6 Abort trap: 6"))
        #expect(record.parameters["has_virtual_memory_region_info"] == .bool(false))
        #expect(record.parameters["app_build_version"] == .string("1.2.3"))
        #expect(record.parameters["os_version"] == .string("iPhone OS 26.0.1 (23A355)"))
        #expect(record.parameters["period_start_unix"] == .int(1_792_713_600))
        #expect(record.parameters["period_end_unix"] == .int(1_792_800_000))

        guard case .string(let message)? = record.parameters["exception_message"] else {
            Issue.record("the composed message is missing from the analytics record")
            return
        }
        #expect(message.count == AppCrashDiagnosticSummary.analyticsMessageLimit, "Firebase Analytics drops a longer parameter value")
        #expect(message.hasPrefix("FIRESTORE INTERNAL ASSERTION FAILED: Failed to commit transaction"))
    }

    @Test("The Sentry message and the diagnostic details carry the whole assertion text, errno included")
    func messageAndDetailsCarryTheWholeText() {
        let summary = summary()
        #expect(summary.messageEventText.hasPrefix("MetricKit crash diagnostic: FIRESTORE INTERNAL ASSERTION FAILED: "))
        #expect(summary.messageEventText.contains("No space left on device (expected created.ok())"))
        #expect(summary.diagnosticDetails["exception_message"] == Self.levelDBAssertion.composedMessage)
        #expect(summary.diagnosticDetails["signal"] == "6")
        #expect(summary.diagnosticDetails["exception_name"] == "FIRESTORE INTERNAL ASSERTION FAILED")
        #expect(summary.diagnosticDetails["fingerprint"] == summary.fingerprint)
    }

    @Test("A diagnostic with no exception reason still names what it can: the signal and the termination reason")
    func summaryWithoutAnExceptionReason() {
        let summary = summary(exceptionReason: nil)
        let record = summary.record
        #expect(record.parameters["has_exception_reason"] == .bool(false))
        #expect(record.parameters["exception_message"] == nil)
        #expect(record.parameters["exception_name"] == nil)
        #expect(summary.messageEventText == "MetricKit crash diagnostic: signal 6 (Namespace SIGNAL, Code 6 Abort trap: 6)")
        #expect(self.summary(exceptionReason: nil, signal: nil, terminationReason: nil).messageEventText == "MetricKit crash diagnostic")
    }

    @Test("The fingerprint is the diagnostic's identity: same facts, same fingerprint; a different crash, a different one")
    func fingerprintIdentity() {
        #expect(summary().fingerprint == summary().fingerprint)
        #expect(summary().fingerprint.count == 64)
        #expect(summary().fingerprint != summary(callStackDigest: "b7c2").fingerprint, "same signal, different stack")
        #expect(summary().fingerprint != summary(exceptionReason: nil).fingerprint)
        var later = summary()
        later.periodStart = later.periodStart.addingTimeInterval(86_400)
        later.periodEnd = later.periodEnd.addingTimeInterval(86_400)
        #expect(summary().fingerprint != later.fingerprint, "the same assertion on another day is another crash")
    }

    @Test("The ledger reports a diagnostic once, survives a relaunch, and stays bounded")
    func ledgerDedupes() {
        let defaults = UserDefaults(suiteName: "crash-ledger-\(UUID().uuidString)")!
        let first = CrashDiagnosticReportLedger(userDefaults: defaults, capacity: 3)
        #expect(first.markReported("a"))
        #expect(!first.markReported("a"), "the second delivery of the same diagnostic is not new")
        #expect(first.hasReported("a"))

        let relaunched = CrashDiagnosticReportLedger(userDefaults: defaults, capacity: 3)
        #expect(!relaunched.markReported("a"), "a redelivery after relaunch is still the same crash")

        #expect(relaunched.markReported("b"))
        #expect(relaunched.markReported("c"))
        #expect(relaunched.markReported("d"))
        #expect(!relaunched.hasReported("a"), "the oldest fingerprint leaves when the ledger is full")
        #expect(relaunched.hasReported("d"))
        #expect(!relaunched.markReported("d"))
    }

    @Test("Reporting sends one analytics event, one error-level diagnostic and one message event, and a redelivered payload sends nothing")
    func reportOnceThroughEveryChannel() {
        let analytics = InMemoryTelemetrySink(destination: .analytics)
        let reporter = RecordingCrashlyticsReporter()
        let telemetry = TelemetryManager(
            sinks: [analytics],
            crashlyticsReporter: reporter,
            collectionEnabledOverride: true,
            identityStore: makeTestIdentityStore()
        )
        telemetry.configure()
        let diagnostics = AppDiagnosticsRecorder(
            userDefaults: UserDefaults(suiteName: "crash-diagnostics-\(UUID().uuidString)")!,
            telemetry: telemetry
        )
        let ledger = ledger()
        let summary = summary()

        #expect(MetricKitExitReporter.report(summary, ledger: ledger, telemetry: telemetry, diagnostics: diagnostics))
        #expect(!MetricKitExitReporter.report(summary, ledger: ledger, telemetry: telemetry, diagnostics: diagnostics), "MetricKit redelivered the payload")

        let events = analytics.records.filter { $0.name == "app_crash_diagnostic" }
        #expect(events.count == 1)
        #expect(events.first?.parameters["exception_name"] == .string("FIRESTORE INTERNAL ASSERTION FAILED"))
        #expect(events.first?.parameters["fingerprint"] == .string(summary.fingerprint))

        let recorded = diagnostics.recentEvents().filter { $0.name == "app_crash_diagnostic_received" }
        #expect(recorded.count == 1)
        #expect(recorded.first?.level == .error)
        #expect(recorded.first?.details["signal"] == "6")
        #expect(recorded.first?.details["exception_message"]?.hasPrefix("FIRESTORE INTERNAL ASSERTION FAILED") == true)

        #expect(reporter.recordedMessages.count == 1)
        #expect(reporter.recordedMessages.first?.message == summary.messageEventText)
        #expect(reporter.recordedMessages.first?.code == "metrickit_crash_diagnostic")
        #expect(reporter.recordedMessages.first?.severity == .error)
        #expect(reporter.recordedMessages.first?.additionalInfo?["exception_message"] == Self.levelDBAssertion.composedMessage)

        let other = self.summary(callStackDigest: "b7c2")
        #expect(MetricKitExitReporter.report(other, ledger: ledger, telemetry: telemetry, diagnostics: diagnostics), "a different crash is reported")
        #expect(reporter.recordedMessages.count == 2)
    }

    @Test("A reporter with no message event of its own keeps the message as a log line")
    func defaultMessageRecordingLogs() {
        let reporter = RecordingBreadcrumbReporter()
        reporter.record(message: "MetricKit crash diagnostic: x", code: "metrickit_crash_diagnostic", additionalInfo: nil, severity: .error)
        #expect(reporter.breadcrumbs.count == 1)
        #expect(reporter.breadcrumbs.first?.message == "[error] metrickit_crash_diagnostic: MetricKit crash diagnostic: x")
    }

    @Test("The message event stays off when collection is off")
    func collectionGateHoldsTheMessage() {
        let reporter = RecordingCrashlyticsReporter()
        let telemetry = TelemetryManager(
            sinks: [],
            crashlyticsReporter: reporter,
            collectionEnabledOverride: false,
            identityStore: makeTestIdentityStore()
        )
        telemetry.configure()
        telemetry.recordMessage("MetricKit crash diagnostic: x", code: "metrickit_crash_diagnostic")
        #expect(reporter.recordedMessages.isEmpty)
    }
}
