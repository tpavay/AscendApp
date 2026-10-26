import Foundation
import UIKit

/// The real phone's answers for `HeadphoneSessionCheckpointDiagnostics`.
///
/// `os_proc_available_memory` is the number jetsam reasons from, so it is the one that says how
/// close the process was to being killed. Free disk is read with the important-usage capacity key,
/// which is the class the draft write belongs to: a phone that refuses that class has refused the
/// checkpoint. Reading it is a required-reason API, declared under E174.1 in
/// `PrivacyInfo.xcprivacy` - the check decides whether a failed write can be retried or must fall
/// back to the JSON file. The `statfs` figure beside it is the one a store write actually fails
/// on, so it is what the recovery sheet names a full phone from.
@MainActor
final class LiveHeadphoneSessionDeviceDiagnostics: HeadphoneSessionDeviceDiagnosticsProviding {
    private let activityClock: AppActivityClock

    init(activityClock: AppActivityClock = .shared) {
        self.activityClock = activityClock
        // Battery readings are -1 until monitoring is on; a session is exactly when they matter.
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    func availableMemoryBytes() -> Int64? {
        let available = os_proc_available_memory()
        guard available > 0 else { return nil }
        return Int64(available)
    }

    func freeDiskBytes() -> Int64? {
        let values = try? URL.applicationSupportDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return values?.volumeAvailableCapacityForImportantUsage
    }

    func writableDiskBytes() -> Int64? {
        VolumeFreeSpaceReader().availableBytes()
    }

    func batteryLevel() -> Double? {
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return nil }
        return Double(level)
    }

    func batteryState() -> String {
        switch UIDevice.current.batteryState {
        case .unplugged:
            return "unplugged"
        case .charging:
            return "charging"
        case .full:
            return "full"
        case .unknown:
            return "unknown"
        @unknown default:
            return "unknown"
        }
    }

    func systemUptime() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    func processUptime() -> TimeInterval {
        TimeInterval(activityClock.secondsSinceLaunch())
    }
}
