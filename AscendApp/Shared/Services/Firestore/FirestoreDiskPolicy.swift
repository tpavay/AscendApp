import Foundation

/// The decisions that keep Firestore's on-device cache off a volume that cannot take a write.
///
/// Firestore stores its cache in LevelDB and wraps every operation - a read as much as a
/// write, because registering a listen allocates a target - in a LevelDB transaction whose
/// commit is `HARD_ASSERT`ed (`leveldb_transaction.cc:218` in the pinned 11.15.0). When the
/// volume has no free blocks the commit fails with `No space left on device`, the assertion
/// throws, and the whole process dies - the step counter, the clock, the Live Activity and the
/// draft checkpointer with it. That is what ended Urjita's Empire State climb 39 seconds after
/// GO on 2026-10-23, and both crash reporters were silenced by the same full volume because
/// each has to create a file at crash time. The maintainers closed the upstream report
/// (firebase-ios-sdk #6727) as a known limitation and advise exactly this: watch free space
/// and run a memory cache when it is low.
///
/// Pure on purpose: every threshold here is a number compared against a byte count, so the
/// boundary is unit-tested rather than discovered on a climber's phone.
enum FirestoreDiskPolicy {
    /// Below this many bytes available to an unprivileged write, Firestore runs in memory and
    /// every cache-writing operation is refused before it reaches LevelDB.
    ///
    /// 200 MiB is far above what one Live Climb writes and far below the headroom iOS itself
    /// tries to keep by purging caches, so reaching it means purging has already lost.
    static let lowDiskFloorBytes: Int64 = 200 * 1024 * 1024

    /// What the persistent cache is bounded to when the volume has room. The SDK's default is
    /// 100 MiB; Ascend reads from the server by design and keeps its own outbox in SwiftData,
    /// so the cache only buys faster re-reads of leaderboard documents and must never be what
    /// fills a phone.
    static let boundedPersistentCacheSizeBytes: Int64 = 20 * 1024 * 1024

    /// The SDK's own default, applied when the policy's kill switch is off so the app runs
    /// exactly as it did before the policy existed.
    static let sdkDefaultPersistentCacheSizeBytes: Int64 = 100 * 1024 * 1024

    /// The cache this process should run with, from the bytes available at launch.
    ///
    /// - Parameters:
    ///   - availableBytes: What `statfs` reports as available to this process, or nil when the
    ///     volume could not be asked - which is answered with memory, because a volume that
    ///     cannot say how full it is is not one to write a database on.
    ///   - isEnabled: The `firestore_memory_cache_on_low_disk_enabled` kill switch.
    static func cacheMode(availableBytes: Int64?, isEnabled: Bool) -> FirestoreCacheMode {
        guard isEnabled else {
            return .persistent(sizeBytes: sdkDefaultPersistentCacheSizeBytes)
        }
        guard let availableBytes, availableBytes >= lowDiskFloorBytes else {
            return .memory
        }
        return .persistent(sizeBytes: boundedPersistentCacheSizeBytes)
    }

    /// Whether a Firestore operation that would write the local cache may run right now.
    ///
    /// A process running in memory writes nothing to the volume, so it is always allowed; a
    /// persistent process is allowed while the volume holds at least the floor. An unreadable
    /// volume refuses, for the same reason `cacheMode` answers it with memory.
    static func allowsLocalCacheWrite(
        cacheMode: FirestoreCacheMode?,
        availableBytes: Int64?,
        isEnabled: Bool
    ) -> Bool {
        guard isEnabled else { return true }
        if let cacheMode, !cacheMode.usesLocalDisk { return true }
        guard let availableBytes else { return false }
        return availableBytes >= lowDiskFloorBytes
    }
}
