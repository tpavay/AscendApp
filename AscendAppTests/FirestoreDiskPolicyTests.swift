import FirebaseCore
import FirebaseFirestore
import Foundation
import Testing
@testable import AscendApp

/// The thresholds that keep Firestore's cache off a full volume, pinned at their boundaries.
struct FirestoreDiskPolicyTests {
    private static let floor = FirestoreDiskPolicy.lowDiskFloorBytes
    private static let bounded = FirestoreCacheMode.persistent(sizeBytes: FirestoreDiskPolicy.boundedPersistentCacheSizeBytes)

    @Test
    func theFloorAndTheBoundAreTheNumbersTheIncidentReportAsksFor() {
        #expect(FirestoreDiskPolicy.lowDiskFloorBytes == 200 * 1024 * 1024)
        #expect(FirestoreDiskPolicy.boundedPersistentCacheSizeBytes == 20 * 1024 * 1024)
        #expect(FirestoreDiskPolicy.sdkDefaultPersistentCacheSizeBytes == 100 * 1024 * 1024)
        #expect(FirestoreDiskPolicy.boundedPersistentCacheSizeBytes < FirestoreDiskPolicy.lowDiskFloorBytes)
    }

    /// The shipped state: no LevelDB in any process, so the commit assertion has nothing to
    /// fire on however full the phone is or becomes.
    @Test(arguments: [nil, Int64(0), floor - 1, floor, floor * 10, Int64.max])
    func withTheSwitchOnFirestoreRunsInMemoryWhateverTheVolumeHolds(availableBytes: Int64?) {
        #expect(FirestoreDiskPolicy.cacheMode(availableBytes: availableBytes, isMemoryCacheEnabled: true) == .memory)
    }

    @Test(arguments: [Int64(0), 1, floor / 2, floor - 1])
    func withTheSwitchOffBelowTheFloorFirestoreStillRunsInMemory(availableBytes: Int64) {
        #expect(FirestoreDiskPolicy.cacheMode(availableBytes: availableBytes, isMemoryCacheEnabled: false) == .memory)
    }

    @Test
    func withTheSwitchOffAVolumeThatCannotBeReadIsAnsweredWithMemory() {
        #expect(FirestoreDiskPolicy.cacheMode(availableBytes: nil, isMemoryCacheEnabled: false) == .memory)
    }

    @Test(arguments: [floor, floor + 1, floor * 10, Int64.max])
    func withTheSwitchOffAtOrAboveTheFloorFirestoreRunsTheBoundedPersistentCache(availableBytes: Int64) {
        #expect(FirestoreDiskPolicy.cacheMode(availableBytes: availableBytes, isMemoryCacheEnabled: false) == Self.bounded)
    }

    @Test(arguments: [nil, Int64(0), floor - 1])
    func aPersistentProcessRefusesACacheWriteBelowTheFloorOrUnread(availableBytes: Int64?) {
        #expect(FirestoreDiskPolicy.allowsLocalCacheWrite(cacheMode: Self.bounded, availableBytes: availableBytes) == false)
    }

    @Test(arguments: [floor, floor + 1, Int64.max])
    func aPersistentProcessAllowsACacheWriteAtOrAboveTheFloor(availableBytes: Int64) {
        #expect(FirestoreDiskPolicy.allowsLocalCacheWrite(cacheMode: Self.bounded, availableBytes: availableBytes))
    }

    /// A memory-cache process has no LevelDB to protect, so it never refuses - a refusal there
    /// would be the guard itself taking the board away from a climber it already saved.
    @Test(arguments: [nil, Int64(0), floor - 1])
    func aMemoryProcessAlwaysAllowsWhateverTheVolumeHolds(availableBytes: Int64?) {
        #expect(FirestoreDiskPolicy.allowsLocalCacheWrite(cacheMode: .memory, availableBytes: availableBytes))
    }

    /// A process whose cache was never decided is treated as the SDK default, which is persistent.
    @Test
    func anUndecidedProcessIsTreatedAsPersistent() {
        #expect(FirestoreDiskPolicy.allowsLocalCacheWrite(cacheMode: nil, availableBytes: Self.floor - 1) == false)
        #expect(FirestoreDiskPolicy.allowsLocalCacheWrite(cacheMode: nil, availableBytes: Self.floor))
    }

    @Test
    func eachModeProducesTheMatchingSDKSettings() {
        #expect(FirestoreCacheMode.memory.makeCacheSettings() is MemoryCacheSettings)
        // The SDK exposes no getter for the size, so the type is what can be pinned here; the
        // bound itself is pinned above and applied by `FirestoreDiskGuard.activate`.
        #expect(Self.bounded.makeCacheSettings() is PersistentCacheSettings)
        #expect(FirestoreCacheMode.memory.usesLocalDisk == false)
        #expect(FirestoreCacheMode.persistent(sizeBytes: 1).usesLocalDisk)
    }

    /// What `AscendApp.configureFirebase()` left on the app's own Firestore in this test host,
    /// which launched with the switch at its shipped default.
    @Test
    func theAppsFirestoreWasConfiguredWithTheMemoryCache() throws {
        try #require(FirebaseApp.app() != nil, "the test host configures Firebase at launch")
        #expect(RemoteFeatureFlag.firestoreMemoryCache.shippedDefault)
        #expect(Firestore.firestore().settings.cacheSettings is MemoryCacheSettings)
    }
}
