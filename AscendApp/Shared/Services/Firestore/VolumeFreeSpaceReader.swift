import Darwin
import Foundation

/// How much of the volume Firestore writes to is still free.
protocol VolumeFreeSpaceReading: Sendable {
    /// Bytes an unprivileged `write(2)` can still use - `statfs` `f_bavail * f_bsize`, the
    /// figure LevelDB's own write sees. Microseconds, so it is safe in front of every read.
    /// Nil when the volume could not be asked.
    func availableBytes() -> Int64?

    /// Apple's "important usage" capacity, which adds the space iOS would reclaim by purging
    /// caches. Recorded beside the raw figure so an investigation can see both; never decided on,
    /// because a purge is a promise and `ENOSPC` is a fact.
    func availableBytesForImportantUsage() -> Int64?
}

/// Reads the volume that holds the app's container, which is where Firestore keeps its cache.
struct VolumeFreeSpaceReader: VolumeFreeSpaceReading {
    private let path: String

    /// - Parameter path: Any path on the volume to read. The home directory always exists and
    ///   shares a volume with `Library/Application Support/firestore`.
    init(path: String = NSHomeDirectory()) {
        self.path = path
    }

    func availableBytes() -> Int64? {
        var stats = statfs()
        guard statfs(path, &stats) == 0 else { return nil }
        return Int64(clamping: stats.f_bavail) * Int64(stats.f_bsize)
    }

    func availableBytesForImportantUsage() -> Int64? {
        let values = try? URL(fileURLWithPath: path)
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
