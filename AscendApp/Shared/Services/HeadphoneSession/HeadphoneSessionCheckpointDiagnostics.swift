import Foundation

/// What the process knew about its own footing the last time it checkpointed a session.
///
/// Written onto the draft at every checkpoint, so the launch that finds the draft can say what
/// happened - "closed by iOS with 180 MB available after two memory warnings" - instead of
/// guessing from a step count and a clock. Every field is optional on the wire: a diagnostic the
/// device could not answer is recorded as unknown rather than as zero, because zero is a reading.
struct HeadphoneSessionCheckpointDiagnostics: Codable, Equatable, Sendable {
    /// `os_proc_available_memory()` at the checkpoint: how much more the process could allocate
    /// before jetsam. Nil where the kernel did not answer.
    var availableMemoryBytes: Int64?
    /// Free space on the volume the store lives on, for the important-usage class the draft
    /// write belongs to.
    var freeDiskBytes: Int64?
    /// How many `didReceiveMemoryWarning` notifications this process had seen since the session
    /// started counting.
    var memoryWarningCount: Int
    /// `UIDevice.batteryLevel`, 0...1, or nil when battery monitoring is unavailable.
    var batteryLevel: Double?
    /// `UIDevice.batteryState` by name: `unplugged`, `charging`, `full`, `unknown`.
    var batteryState: String
    /// The `HKWorkoutSession` state by name, as `LiveClimbBackgroundSessionService` last saw it.
    var workoutSessionState: String
    /// The headphone-motion status by name at the checkpoint.
    var motionStatus: String
    /// `ProcessInfo.systemUptime` at the checkpoint. A later launch whose uptime is shorter than
    /// the time since this checkpoint knows the phone rebooted in between: the one durable
    /// signature of a battery that ran out or a phone that was switched off.
    var systemUptimeSeconds: TimeInterval
    /// Seconds since the app process launched, so a death can be placed on the process timeline.
    var processUptimeSeconds: TimeInterval
    var recordedAt: Date

    init(
        availableMemoryBytes: Int64? = nil,
        freeDiskBytes: Int64? = nil,
        memoryWarningCount: Int = 0,
        batteryLevel: Double? = nil,
        batteryState: String = "unknown",
        workoutSessionState: String = "unknown",
        motionStatus: String = "unknown",
        systemUptimeSeconds: TimeInterval,
        processUptimeSeconds: TimeInterval,
        recordedAt: Date
    ) {
        self.availableMemoryBytes = availableMemoryBytes
        self.freeDiskBytes = freeDiskBytes
        self.memoryWarningCount = memoryWarningCount
        self.batteryLevel = batteryLevel
        self.batteryState = batteryState
        self.workoutSessionState = workoutSessionState
        self.motionStatus = motionStatus
        self.systemUptimeSeconds = systemUptimeSeconds
        self.processUptimeSeconds = processUptimeSeconds
        self.recordedAt = recordedAt
    }

    /// The same facts as flat strings, for `AppDiagnosticsRecorder` and analytics.
    var diagnosticDetails: [String: String] {
        var details: [String: String] = [
            "memory_warning_count": String(memoryWarningCount),
            "battery_state": batteryState,
            "hk_session_state": workoutSessionState,
            "motion_status": motionStatus,
            "system_uptime_seconds": String(Int(systemUptimeSeconds.rounded(.down))),
            "process_uptime_seconds": String(Int(processUptimeSeconds.rounded(.down)))
        ]
        if let availableMemoryBytes {
            details["available_memory_mb"] = String(availableMemoryBytes / 1_048_576)
        }
        if let freeDiskBytes {
            details["free_disk_mb"] = String(freeDiskBytes / 1_048_576)
        }
        if let batteryLevel {
            details["battery_percent"] = String(Int((batteryLevel * 100).rounded()))
        }
        return details
    }
}

/// The device readings a checkpoint records, behind a seam so a test can hand a session a phone
/// that is nearly out of memory, out of disk, or about to reboot.
@MainActor
protocol HeadphoneSessionDeviceDiagnosticsProviding: AnyObject {
    func availableMemoryBytes() -> Int64?
    func freeDiskBytes() -> Int64?
    func batteryLevel() -> Double?
    func batteryState() -> String
    func systemUptime() -> TimeInterval
    func processUptime() -> TimeInterval
}
