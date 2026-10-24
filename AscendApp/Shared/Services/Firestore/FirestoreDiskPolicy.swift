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
/// Ascend runs a memory cache always, so the assertion has no LevelDB to fire on. The bounded
/// persistent cache exists only behind the `firestore_memory_cache_enabled` kill switch, and a
/// process that takes it still runs in memory below the floor and still refuses cache writes
/// once the volume reaches it.
///
/// Pure on purpose: every threshold here is a number compared against a byte count, so the
/// boundary is unit-tested rather than discovered on a climber's phone.
enum FirestoreDiskPolicy {
    /// Below this many bytes available to an unprivileged write the volume is at the floor: a
    /// launch reports it, a persistent cache is not opened, and every cache-writing operation
    /// of a persistent process is refused before it reaches LevelDB.
    ///
    /// 200 MiB is far above what one Live Climb writes and far below the headroom iOS itself
    /// tries to keep by purging caches, so reaching it means purging has already lost.
    static let lowDiskFloorBytes: Int64 = 200 * 1024 * 1024

    /// What the persistent cache is bounded to when the kill switch turns it on. The SDK's
    /// default is 100 MiB; Ascend reads from the server by design and keeps its own outbox in
    /// SwiftData, so the cache only buys faster re-reads of leaderboard documents and must
    /// never be what fills a phone.
    static let boundedPersistentCacheSizeBytes: Int64 = 20 * 1024 * 1024

    /// The SDK's own default, which a Firestore instance nobody configured runs with.
    static let sdkDefaultPersistentCacheSizeBytes: Int64 = 100 * 1024 * 1024

    /// Whether a reading is at or above the floor. An unreadable volume is not, because a
    /// volume that cannot say how full it is is not one to write a database on.
    static func isAboveFloor(_ availableBytes: Int64?) -> Bool {
        guard let availableBytes else { return false }
        return availableBytes >= lowDiskFloorBytes
    }

    /// The cache this process should run with.
    ///
    /// - Parameters:
    ///   - availableBytes: What `statfs` reports as available to this process at launch, or
    ///     nil when the volume could not be asked.
    ///   - isMemoryCacheEnabled: The `firestore_memory_cache_enabled` kill switch. On - the
    ///     shipped state - is a memory cache whatever the volume holds.
    static func cacheMode(availableBytes: Int64?, isMemoryCacheEnabled: Bool) -> FirestoreCacheMode {
        guard !isMemoryCacheEnabled, isAboveFloor(availableBytes) else {
            return .memory
        }
        return .persistent(sizeBytes: boundedPersistentCacheSizeBytes)
    }

    /// Whether a Firestore operation that would write the local cache may run right now.
    ///
    /// A process running in memory writes nothing to the volume, so it is always allowed; a
    /// persistent process - or one whose cache was never decided, which is the SDK's default
    /// persistent cache - is allowed while the volume holds at least the floor.
    static func allowsLocalCacheWrite(cacheMode: FirestoreCacheMode?, availableBytes: Int64?) -> Bool {
        if let cacheMode, !cacheMode.usesLocalDisk { return true }
        return isAboveFloor(availableBytes)
    }
}
