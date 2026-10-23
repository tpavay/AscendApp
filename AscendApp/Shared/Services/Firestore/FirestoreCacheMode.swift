import FirebaseFirestore
import Foundation

/// Which cache this process runs Firestore with. Decided once, before the first
/// `Firestore.firestore()` use, by `FirestoreDiskGuard` from `FirestoreDiskPolicy`.
enum FirestoreCacheMode: Equatable, Sendable {
    /// No LevelDB at all. Every read is answered by the server or from memory, so Firestore's
    /// `LevelDbTransaction::Commit()` assertion - which aborts the process the moment a cache
    /// write fails - cannot fire in this process whatever the volume does.
    case memory

    /// The SDK's LevelDB cache, bounded to `sizeBytes`. The SDK garbage-collects the cache
    /// down to this size, so the bound is also the most the cache itself can ever occupy.
    case persistent(sizeBytes: Int64)

    /// Whether this mode writes to the volume at all.
    var usesLocalDisk: Bool {
        switch self {
        case .memory: false
        case .persistent: true
        }
    }

    /// The SDK settings object for this mode.
    func makeCacheSettings() -> any LocalCacheSettings & NSObjectProtocol {
        switch self {
        case .memory:
            MemoryCacheSettings()
        case .persistent(let sizeBytes):
            PersistentCacheSettings(sizeBytes: NSNumber(value: sizeBytes))
        }
    }

    /// The bounded label analytics and diagnostics carry.
    var analyticsValue: String {
        switch self {
        case .memory: "memory"
        case .persistent: "persistent"
        }
    }
}
