import Foundation
import Testing
@testable import AscendApp

/// The signals that make a lost session visible within minutes: the two analytics events, the
/// leveled Sentry breadcrumbs, the MetricKit exit summary and the heartbeat document.
struct HeadphoneSessionDetectionTests {
    @Test("live_climb_session_lost carries what the draft knew and how the launch read it")
    func sessionLostRecord() {
        let record = HeadphoneSessionRecoveryAnalyticsEvent.sessionLost(
            mode: .liveClimb,
            draftAgeSeconds: 1_165,
            steps: 66,
            durationSeconds: 62,
            lastWorkoutSessionState: "running",
            availableMemoryMB: 180,
            memoryWarningCount: 2,
            lossReason: .closedByIOS,
            plan: .autoResume
        ).record

        #expect(record.name == "live_climb_session_lost")
        #expect(record.parameters["mode"] == .string("live_climb"))
        #expect(record.parameters["draft_age_seconds"] == .int(1_165))
        #expect(record.parameters["steps"] == .int(66))
        #expect(record.parameters["duration_seconds"] == .int(62))
        #expect(record.parameters["last_hk_session_state"] == .string("running"))
        #expect(record.parameters["available_memory_mb"] == .int(180))
        #expect(record.parameters["memory_warning_count"] == .int(2))
        #expect(record.parameters["loss_reason"] == .string("closed_by_ios"))
        #expect(record.parameters["plan"] == .string("auto_resume"))
        #expect(record.destinations == [.analytics])
    }

    @Test("live_climb_session_resumed names the gap, where its steps came from, and what the climber did")
    func sessionResumedRecord() {
        let record = HeadphoneSessionRecoveryAnalyticsEvent.sessionResumed(
            mode: .routine,
            gapSeconds: 1_165,
            lossReason: .phoneOff,
            source: .machine,
            deltaSteps: 1_527,
            action: .save
        ).record

        #expect(record.name == "live_climb_session_resumed")
        #expect(record.parameters["mode"] == .string("routine"))
        #expect(record.parameters["gap_seconds"] == .int(1_165))
        #expect(record.parameters["loss_reason"] == .string("phone_off"))
        #expect(record.parameters["gap_source"] == .string("machine"))
        #expect(record.parameters["delta_steps"] == .int(1_527))
        #expect(record.parameters["action"] == .string("save"))
    }

    @Test("A diagnostic keeps its level on the way to Sentry; ordinary telemetry is an info crumb")
    func breadcrumbLevels() {
        let envelope = TelemetryEnvelope(resolving: .current)
        let diagnostic = AppDiagnosticEvent(
            name: "active_headphone_draft_checkpoint_failed",
            level: .error,
            details: ["error": "The disk is full.", "free_disk_mb": "12"]
        )
        let record = EnvelopedTelemetryRecord(
            record: TelemetryRecord(
                name: "diagnostic:\(diagnostic.name)",
                parameters: [
                    "diagnostic_id": .string(diagnostic.id.uuidString),
                    "diagnostic_level": .string(diagnostic.level.rawValue),
                    "error": .string("The disk is full."),
                    "free_disk_mb": .string("12")
                ],
                destinations: [.crashlytics]
            ),
            envelope: envelope
        )

        let breadcrumb = CrashlyticsBreadcrumbSink.breadcrumb(for: record)
        #expect(breadcrumb.level == .error)
        #expect(breadcrumb.category == "ascend.diagnostic")
        #expect(breadcrumb.message.hasPrefix("diagnostic:active_headphone_draft_checkpoint_failed"))
        #expect(breadcrumb.data["error"] == "The disk is full.")
        #expect(breadcrumb.data["free_disk_mb"] == "12")
        #expect(breadcrumb.data["diagnostic_id"] == nil)
        #expect(breadcrumb.data["app_version"] == nil, "envelope properties are tags, not crumb data")
        #expect(breadcrumb.logLine.hasPrefix("[error] "))

        let warning = CrashlyticsBreadcrumbSink.breadcrumb(for: EnvelopedTelemetryRecord(
            record: TelemetryRecord(
                name: "diagnostic:memory_warning_received",
                parameters: ["diagnostic_level": .string("warning")],
                destinations: [.crashlytics]
            ),
            envelope: envelope
        ))
        #expect(warning.level == .warning)

        let plain = CrashlyticsBreadcrumbSink.breadcrumb(for: EnvelopedTelemetryRecord(
            record: TelemetryRecord(name: "live_climb_attempt_started", destinations: [.crashlytics]),
            envelope: envelope
        ))
        #expect(plain.level == .info)
        #expect(plain.category == "ascend.telemetry")
        #expect(plain.data.isEmpty)
        #expect(plain.logLine == plain.message)
    }

    @Test("Every recorder warning and error reaches the crash reporters as a leveled breadcrumb")
    func recorderForwardsLeveledBreadcrumbs() {
        let reporter = RecordingBreadcrumbReporter()
        let sink = CrashlyticsBreadcrumbSink(reporter: reporter)
        let telemetry = TelemetryManager(
            sinks: [sink],
            crashlyticsReporter: reporter,
            collectionEnabledOverride: true
        )
        telemetry.configure()
        let defaults = UserDefaults(suiteName: "breadcrumbs-\(UUID().uuidString)")!
        let recorder = AppDiagnosticsRecorder(userDefaults: defaults, telemetry: telemetry)

        recorder.record("headphone_session_lost", level: .warning, details: ["gap_seconds": "1165"])
        recorder.record("active_headphone_draft_checkpoint_failed", level: .error, details: ["error": "full"])
        recorder.record("scene_connected", level: .info)

        #expect(reporter.breadcrumbs.map(\.level) == [.warning, .error, .info])
        #expect(reporter.breadcrumbs[0].data["gap_seconds"] == "1165")
        #expect(reporter.breadcrumbs[1].message.contains("active_headphone_draft_checkpoint_failed"))
    }

    @Test("A day's MetricKit exits become one event and one diagnostic, abnormal exits totalled")
    func exitMetricsSummary() {
        let summary = AppExitMetricsSummary(
            periodStart: Date(timeIntervalSince1970: 1_792_713_600),
            periodEnd: Date(timeIntervalSince1970: 1_792_800_000),
            background: .init(
                normal: 12, memoryResourceLimit: 0, cpuResourceLimit: 0, memoryPressure: 3,
                badAccess: 0, abnormal: 0, illegalInstruction: 0, appWatchdog: 1,
                suspendedWithLockedFile: 0, backgroundTaskAssertionTimeout: 0
            ),
            foreground: .init(
                normal: 4, memoryResourceLimit: 1, cpuResourceLimit: 0, memoryPressure: 0,
                badAccess: 0, abnormal: 0, illegalInstruction: 0, appWatchdog: 0,
                suspendedWithLockedFile: 0, backgroundTaskAssertionTimeout: 0
            )
        )

        let record = summary.record
        #expect(record.name == "app_exit_metrics")
        #expect(record.parameters["background_memory_pressure"] == .int(3))
        #expect(record.parameters["background_app_watchdog"] == .int(1))
        #expect(record.parameters["background_abnormal_total"] == .int(4))
        #expect(record.parameters["foreground_memory_resource_limit"] == .int(1))
        #expect(record.parameters["period_start_unix"] == .int(1_792_713_600))
        #expect(summary.diagnosticDetails["background_memory_pressure"] == "3")
        #expect(summary.diagnosticDetails["foreground_abnormal_total"] == "1")
        #expect(summary.background.abnormalTotal == 4)
    }

    @Test("The heartbeat document is exactly the field set the rules admit, open and ended")
    func heartbeatDocumentShape() {
        let open = AttemptHeartbeat(
            sessionID: "s1", mode: .justClimb, steps: 66, durationSeconds: 62,
            startedAt: Date(timeIntervalSince1970: 1_792_754_454), climbId: nil,
            state: .open, outcome: nil
        )
        let openDocument = FirestoreAttemptHeartbeatRepository.document(for: open, appVersion: "1.2.3")
        #expect(Set(openDocument.keys) == [
            "schemaVersion", "sessionID", "mode", "steps", "durationSeconds", "startedAt",
            "lastSeenAt", "state", "endedAt", "outcome", "climbId", "appVersion"
        ])
        #expect(openDocument["mode"] as? String == "just_climb")
        #expect(openDocument["state"] as? String == "open")
        #expect(openDocument["steps"] as? Int == 66)
        #expect(openDocument["climbId"] is NSNull)
        #expect(openDocument["endedAt"] is NSNull)

        let ended = AttemptHeartbeat(
            sessionID: "s1", mode: .liveClimb, steps: 1_576, durationSeconds: 1_172,
            startedAt: Date(timeIntervalSince1970: 1_792_754_454), climbId: "empire-state-building",
            state: .ended, outcome: .saved
        )
        let endedDocument = FirestoreAttemptHeartbeatRepository.document(for: ended, appVersion: "1.2.3")
        #expect(endedDocument["state"] as? String == "ended")
        #expect(endedDocument["outcome"] as? String == "saved")
        #expect(endedDocument["climbId"] as? String == "empire-state-building")
        #expect(!(endedDocument["endedAt"] is NSNull))

        #expect(AttemptHeartbeatPolicy.isDue(lastPublishedAt: nil, now: Date()))
        let now = Date()
        #expect(!AttemptHeartbeatPolicy.isDue(lastPublishedAt: now.addingTimeInterval(-59), now: now))
        #expect(AttemptHeartbeatPolicy.isDue(lastPublishedAt: now.addingTimeInterval(-60), now: now))
    }
}

/// A crash reporter that keeps the breadcrumbs it is handed.
final class RecordingBreadcrumbReporter: CrashlyticsReporting, @unchecked Sendable {
    private let lock = NSLock()
    private var _breadcrumbs: [TelemetryBreadcrumb] = []

    var breadcrumbs: [TelemetryBreadcrumb] { lock.withLock { _breadcrumbs } }

    func setCollectionEnabled(_ enabled: Bool) {}
    func setUserID(_ userID: String?) {}
    func setCustomValue(_ value: Bool, forKey key: String) {}
    func setCustomValue(_ value: Int, forKey key: String) {}
    func setCustomValue(_ value: String, forKey key: String) {}
    func log(_ message: String) {
        addBreadcrumb(TelemetryBreadcrumb(category: "ascend.telemetry", message: message, level: .info))
    }
    func addBreadcrumb(_ breadcrumb: TelemetryBreadcrumb) {
        lock.withLock { _breadcrumbs.append(breadcrumb) }
    }
    func record(error: Error, context: String, code: String, additionalInfo: [String: String]?, severity: TelemetryErrorSeverity) {}
}
