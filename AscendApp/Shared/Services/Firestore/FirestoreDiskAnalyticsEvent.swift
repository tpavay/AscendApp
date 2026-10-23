import Foundation

/// The one telemetry event the low-disk policy emits, so the next investigation can see how
/// full the phone was instead of inferring it from a crash report that never arrived.
enum FirestoreDiskAnalyticsEvent: TelemetryEvent {
    enum Trigger: String, Sendable {
        /// The launch decision put this process on a memory cache.
        case launchMemoryCache = "launch_memory_cache"
        /// A persistent-cache process refused its first cache-writing operation mid-session.
        case readGate = "read_gate"
    }

    case lowDiskMode(
        trigger: Trigger,
        cacheMode: FirestoreCacheMode,
        availableBytes: Int64?,
        availableBytesForImportantUsage: Int64?
    )

    var record: TelemetryRecord {
        switch self {
        case .lowDiskMode(let trigger, let cacheMode, let availableBytes, let importantUsageBytes):
            var parameters: [String: TelemetryValue] = [
                "trigger": .string(trigger.rawValue),
                "cache_mode": .string(cacheMode.analyticsValue)
            ]
            if let availableBytes {
                parameters["free_bytes"] = .int(Int(clamping: availableBytes))
            }
            if let importantUsageBytes {
                parameters["important_free_bytes"] = .int(Int(clamping: importantUsageBytes))
            }
            return TelemetryRecord(name: "firestore_low_disk_mode", parameters: parameters)
        }
    }
}
