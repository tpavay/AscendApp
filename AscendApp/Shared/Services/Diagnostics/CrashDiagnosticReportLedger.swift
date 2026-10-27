import Foundation
import os.lock

/// Which crash diagnostics this installation has already reported, so a payload MetricKit
/// delivers twice - redelivered after a launch that did not finish handling it, or replayed from
/// `pastDiagnosticPayloads` - is reported once.
///
/// Persisted in `UserDefaults` because the redelivery that matters is across launches; bounded
/// because a ledger of every crash an installation ever had would be the only thing in Ascend
/// that grows without a ceiling. An installation that crashes more than the ceiling between two
/// launches has a bigger problem than a duplicate report.
final class CrashDiagnosticReportLedger: @unchecked Sendable {
    static let shared = CrashDiagnosticReportLedger()

    static let defaultCapacity = 64

    private let userDefaults: UserDefaults
    private let key: String
    private let capacity: Int
    private let lock = OSAllocatedUnfairLock(initialState: ())

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "metricKit.crashDiagnostics.reported.v1",
        capacity: Int = CrashDiagnosticReportLedger.defaultCapacity
    ) {
        self.userDefaults = userDefaults
        self.key = key
        self.capacity = max(capacity, 1)
    }

    /// Records the fingerprint and says whether it was new. The check and the write are one
    /// step under the lock, so two deliveries of the same diagnostic cannot both be first.
    func markReported(_ fingerprint: String) -> Bool {
        lock.withLock {
            var reported = userDefaults.stringArray(forKey: key) ?? []
            guard !reported.contains(fingerprint) else { return false }
            reported.append(fingerprint)
            if reported.count > capacity {
                reported.removeFirst(reported.count - capacity)
            }
            userDefaults.set(reported, forKey: key)
            return true
        }
    }

    func hasReported(_ fingerprint: String) -> Bool {
        lock.withLock {
            userDefaults.stringArray(forKey: key)?.contains(fingerprint) ?? false
        }
    }
}
