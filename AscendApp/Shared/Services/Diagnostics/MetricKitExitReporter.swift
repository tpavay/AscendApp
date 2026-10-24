import Foundation
import MetricKit

/// How often the system ended Ascend in the background, and why, per day.
///
/// `MXAppExitMetric` is the only API that counts jetsam deaths for an app - nothing else on the
/// phone reports a background memory-pressure kill - and until this existed Ascend did not read
/// it. Each daily payload is forwarded as one analytics event and one diagnostic, so a week of
/// `memory_pressure` exits shows up in Mixpanel and Sentry rather than in a climber's complaint.
struct AppExitMetricsSummary: Equatable, Sendable {
    struct Exits: Equatable, Sendable {
        var normal: Int
        var memoryResourceLimit: Int
        var cpuResourceLimit: Int
        var memoryPressure: Int
        var badAccess: Int
        var abnormal: Int
        var illegalInstruction: Int
        var appWatchdog: Int
        var suspendedWithLockedFile: Int
        var backgroundTaskAssertionTimeout: Int

        var parameters: [String: TelemetryValue] {
            [
                "normal": .int(normal),
                "memory_resource_limit": .int(memoryResourceLimit),
                "cpu_resource_limit": .int(cpuResourceLimit),
                "memory_pressure": .int(memoryPressure),
                "bad_access": .int(badAccess),
                "abnormal": .int(abnormal),
                "illegal_instruction": .int(illegalInstruction),
                "app_watchdog": .int(appWatchdog),
                "suspended_with_locked_file": .int(suspendedWithLockedFile),
                "background_task_assertion_timeout": .int(backgroundTaskAssertionTimeout)
            ]
        }

        /// Everything but a normal exit: the deaths the climber did not choose.
        var abnormalTotal: Int {
            memoryResourceLimit + cpuResourceLimit + memoryPressure + badAccess + abnormal +
                illegalInstruction + appWatchdog + suspendedWithLockedFile + backgroundTaskAssertionTimeout
        }
    }

    let periodStart: Date
    let periodEnd: Date
    let background: Exits
    let foreground: Exits?

    /// The analytics record: one event per daily payload, background counts flat, foreground
    /// counts prefixed.
    var record: TelemetryRecord {
        var parameters: [String: TelemetryValue] = [
            "period_start_unix": .int(Int(periodStart.timeIntervalSince1970)),
            "period_end_unix": .int(Int(periodEnd.timeIntervalSince1970)),
            "background_abnormal_total": .int(background.abnormalTotal)
        ]
        for (key, value) in background.parameters {
            parameters["background_\(key)"] = value
        }
        if let foreground {
            for (key, value) in foreground.parameters {
                parameters["foreground_\(key)"] = value
            }
        }
        return TelemetryRecord(name: "app_exit_metrics", parameters: parameters)
    }

    var diagnosticDetails: [String: String] {
        var details = [
            "background_memory_pressure": String(background.memoryPressure),
            "background_memory_resource_limit": String(background.memoryResourceLimit),
            "background_app_watchdog": String(background.appWatchdog),
            "background_bad_access": String(background.badAccess),
            "background_abnormal_total": String(background.abnormalTotal)
        ]
        if let foreground {
            details["foreground_abnormal_total"] = String(foreground.abnormalTotal)
        }
        return details
    }
}

final class MetricKitExitReporter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MetricKitExitReporter()

    private var didStart = false

    func start() {
        guard !didStart else { return }
        didStart = true
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            guard let summary = Self.summary(from: payload) else { continue }
            Self.report(summary)
        }
    }

    static func report(_ summary: AppExitMetricsSummary) {
        TelemetryManager.shared.track(summary.record)
        AppDiagnosticsRecorder.shared.record(
            "app_exit_metrics_received",
            level: summary.background.abnormalTotal > 0 ? .warning : .info,
            details: summary.diagnosticDetails
        )
    }

    static func summary(from payload: MXMetricPayload) -> AppExitMetricsSummary? {
        guard let exitMetrics = payload.applicationExitMetrics else { return nil }
        return AppExitMetricsSummary(
            periodStart: payload.timeStampBegin,
            periodEnd: payload.timeStampEnd,
            background: exits(exitMetrics.backgroundExitData),
            foreground: exits(exitMetrics.foregroundExitData)
        )
    }

    private static func exits(_ data: MXBackgroundExitData) -> AppExitMetricsSummary.Exits {
        AppExitMetricsSummary.Exits(
            normal: data.cumulativeNormalAppExitCount,
            memoryResourceLimit: data.cumulativeMemoryResourceLimitExitCount,
            cpuResourceLimit: data.cumulativeCPUResourceLimitExitCount,
            memoryPressure: data.cumulativeMemoryPressureExitCount,
            badAccess: data.cumulativeBadAccessExitCount,
            abnormal: data.cumulativeAbnormalExitCount,
            illegalInstruction: data.cumulativeIllegalInstructionExitCount,
            appWatchdog: data.cumulativeAppWatchdogExitCount,
            suspendedWithLockedFile: data.cumulativeSuspendedWithLockedFileExitCount,
            backgroundTaskAssertionTimeout: data.cumulativeBackgroundTaskAssertionTimeoutExitCount
        )
    }

    private static func exits(_ data: MXForegroundExitData) -> AppExitMetricsSummary.Exits {
        AppExitMetricsSummary.Exits(
            normal: data.cumulativeNormalAppExitCount,
            memoryResourceLimit: data.cumulativeMemoryResourceLimitExitCount,
            cpuResourceLimit: 0,
            memoryPressure: 0,
            badAccess: data.cumulativeBadAccessExitCount,
            abnormal: data.cumulativeAbnormalExitCount,
            illegalInstruction: data.cumulativeIllegalInstructionExitCount,
            appWatchdog: data.cumulativeAppWatchdogExitCount,
            suspendedWithLockedFile: 0,
            backgroundTaskAssertionTimeout: 0
        )
    }
}
