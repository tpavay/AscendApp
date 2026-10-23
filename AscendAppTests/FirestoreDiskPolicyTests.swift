import FirebaseFirestore
import Foundation
import Testing
@testable import AscendApp

/// The thresholds that keep Firestore's cache off a full volume, pinned at their boundaries.
struct FirestoreDiskPolicyTests {
    private static let floor = FirestoreDiskPolicy.lowDiskFloorBytes

    @Test
    func theFloorAndTheBoundAreTheNumbersTheIncidentReportAsksFor() {
        #expect(FirestoreDiskPolicy.lowDiskFloorBytes == 200 * 1024 * 1024)
        #expect(FirestoreDiskPolicy.boundedPersistentCacheSizeBytes == 20 * 1024 * 1024)
        #expect(FirestoreDiskPolicy.sdkDefaultPersistentCacheSizeBytes == 100 * 1024 * 1024)
        #expect(FirestoreDiskPolicy.boundedPersistentCacheSizeBytes < FirestoreDiskPolicy.lowDiskFloorBytes)
    }

    @Test(arguments: [Int64(0), 1, floor / 2, floor - 1])
    func belowTheFloorFirestoreRunsInMemory(availableBytes: Int64) {
        #expect(FirestoreDiskPolicy.cacheMode(availableBytes: availableBytes, isEnabled: true) == .memory)
    }

    @Test(arguments: [floor, floor + 1, floor * 10, Int64.max])
    func atOrAboveTheFloorFirestoreRunsABoundedPersistentCache(availableBytes: Int64) {
        #expect(
            FirestoreDiskPolicy.cacheMode(availableBytes: availableBytes, isEnabled: true)
                == .persistent(sizeBytes: FirestoreDiskPolicy.boundedPersistentCacheSizeBytes)
        )
    }

    @Test
    func aVolumeThatCannotBeReadIsAnsweredWithMemory() {
        #expect(FirestoreDiskPolicy.cacheMode(availableBytes: nil, isEnabled: true) == .memory)
    }

    @Test(arguments: [nil, Int64(0), floor - 1, floor, Int64.max])
    func theKillSwitchOffRestoresTheSDKsDefaultWhateverTheVolumeHolds(availableBytes: Int64?) {
        #expect(
            FirestoreDiskPolicy.cacheMode(availableBytes: availableBytes, isEnabled: false)
                == .persistent(sizeBytes: FirestoreDiskPolicy.sdkDefaultPersistentCacheSizeBytes)
        )
    }

    @Test(arguments: [Int64(0), floor - 1])
    func aPersistentProcessRefusesACacheWriteBelowTheFloor(availableBytes: Int64) {
        #expect(
            FirestoreDiskPolicy.allowsLocalCacheWrite(
                cacheMode: .persistent(sizeBytes: FirestoreDiskPolicy.boundedPersistentCacheSizeBytes),
                availableBytes: availableBytes,
                isEnabled: true
            ) == false
        )
    }

    @Test(arguments: [floor, floor + 1, Int64.max])
    func aPersistentProcessAllowsACacheWriteAtOrAboveTheFloor(availableBytes: Int64) {
        #expect(
            FirestoreDiskPolicy.allowsLocalCacheWrite(
                cacheMode: .persistent(sizeBytes: FirestoreDiskPolicy.boundedPersistentCacheSizeBytes),
                availableBytes: availableBytes,
                isEnabled: true
            )
        )
    }

    /// A memory-cache process has no LevelDB to protect, so it never refuses - a refusal there
    /// would be the guard itself taking the board away from a climber it already saved.
    @Test(arguments: [nil, Int64(0), floor - 1])
    func aMemoryProcessAlwaysAllowsWhateverTheVolumeHolds(availableBytes: Int64?) {
        #expect(FirestoreDiskPolicy.allowsLocalCacheWrite(cacheMode: .memory, availableBytes: availableBytes, isEnabled: true))
    }

    /// A process whose cache was never decided is treated as the SDK default, which is persistent.
    @Test
    func anUndecidedProcessIsTreatedAsPersistent() {
        #expect(FirestoreDiskPolicy.allowsLocalCacheWrite(cacheMode: nil, availableBytes: Self.floor - 1, isEnabled: true) == false)
        #expect(FirestoreDiskPolicy.allowsLocalCacheWrite(cacheMode: nil, availableBytes: Self.floor, isEnabled: true))
    }

    @Test
    func aPersistentProcessWhoseVolumeCannotBeReadRefuses() {
        #expect(
            FirestoreDiskPolicy.allowsLocalCacheWrite(
                cacheMode: .persistent(sizeBytes: FirestoreDiskPolicy.boundedPersistentCacheSizeBytes),
                availableBytes: nil,
                isEnabled: true
            ) == false
        )
    }

    @Test(arguments: [nil, Int64(0), floor - 1])
    func theKillSwitchOffDisarmsTheGate(availableBytes: Int64?) {
        #expect(
            FirestoreDiskPolicy.allowsLocalCacheWrite(
                cacheMode: .persistent(sizeBytes: FirestoreDiskPolicy.sdkDefaultPersistentCacheSizeBytes),
                availableBytes: availableBytes,
                isEnabled: false
            )
        )
    }

    @Test
    func eachModeProducesTheMatchingSDKSettings() {
        #expect(FirestoreCacheMode.memory.makeCacheSettings() is MemoryCacheSettings)
        // The SDK exposes no getter for the size, so the type is what can be pinned here; the
        // bound itself is pinned above and applied by `FirestoreDiskGuard.activate`.
        #expect(FirestoreCacheMode.persistent(sizeBytes: 20 * 1024 * 1024).makeCacheSettings() is PersistentCacheSettings)
        #expect(FirestoreCacheMode.memory.usesLocalDisk == false)
        #expect(FirestoreCacheMode.persistent(sizeBytes: 1).usesLocalDisk)
    }
}
