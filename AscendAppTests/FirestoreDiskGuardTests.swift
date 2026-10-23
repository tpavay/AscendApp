import Foundation
import Testing
@testable import AscendApp

/// What the process-wide guard records and reports, with the volume scripted.
struct FirestoreDiskGuardTests {
    private static let floor = FirestoreDiskPolicy.lowDiskFloorBytes

    @Test
    func aFullVolumeAtLaunchChoosesMemoryAndReportsItOnce() {
        let volume = ScriptedVolume(availableBytes: 1_000, importantUsageBytes: 5_000)
        let diagnostics = SpyDiagnosticsRecorder()
        let telemetry = RecordedTelemetry()
        let guardUnderTest = FirestoreDiskGuard(
            freeSpace: volume,
            featureFlags: RemoteFeatureFlagStore(),
            diagnostics: diagnostics,
            telemetry: telemetry.track
        )

        let mode = guardUnderTest.decideCacheMode()

        #expect(mode == .memory)
        #expect(guardUnderTest.cacheMode == .memory)
        #expect(guardUnderTest.allowsLocalCacheWrite())
        #expect(diagnostics.events.map(\.name) == ["firestore_low_disk_mode"])
        #expect(diagnostics.events.first?.details["trigger"] == "launch_memory_cache")
        #expect(diagnostics.events.first?.details["free_bytes"] == "1000")
        #expect(diagnostics.events.first?.details["important_free_bytes"] == "5000")
        let records = telemetry.records
        #expect(records.map(\.name) == ["firestore_low_disk_mode"])
        #expect(records.first?.parameters["trigger"] == .string("launch_memory_cache"))
        #expect(records.first?.parameters["cache_mode"] == .string("memory"))
        #expect(records.first?.parameters["free_bytes"] == .int(1_000))
        #expect(records.first?.parameters["important_free_bytes"] == .int(5_000))
    }

    @Test
    func aRoomyVolumeAtLaunchChoosesTheBoundedCacheAndStaysQuiet() {
        let volume = ScriptedVolume(availableBytes: Self.floor * 4, importantUsageBytes: nil)
        let diagnostics = SpyDiagnosticsRecorder()
        let telemetry = RecordedTelemetry()
        let guardUnderTest = FirestoreDiskGuard(
            freeSpace: volume,
            featureFlags: RemoteFeatureFlagStore(),
            diagnostics: diagnostics,
            telemetry: telemetry.track
        )

        let mode = guardUnderTest.decideCacheMode()

        #expect(mode == .persistent(sizeBytes: FirestoreDiskPolicy.boundedPersistentCacheSizeBytes))
        #expect(guardUnderTest.allowsLocalCacheWrite())
        #expect(diagnostics.events.isEmpty)
        #expect(telemetry.records.isEmpty)
    }

    /// The Empire State case: fine at launch, full 39 seconds into the climb. The gate trips,
    /// reports the first refusal once, and keeps refusing silently until the volume has room.
    @Test
    func aVolumeThatFillsMidSessionTripsTheGateAndReportsTheFirstRefusalOnly() {
        let volume = ScriptedVolume(availableBytes: Self.floor * 4, importantUsageBytes: 10)
        let diagnostics = SpyDiagnosticsRecorder()
        let telemetry = RecordedTelemetry()
        let guardUnderTest = FirestoreDiskGuard(
            freeSpace: volume,
            featureFlags: RemoteFeatureFlagStore(),
            diagnostics: diagnostics,
            telemetry: telemetry.track
        )
        guardUnderTest.decideCacheMode()
        #expect(guardUnderTest.allowsLocalCacheWrite())

        volume.freeBytes = 0
        #expect(guardUnderTest.allowsLocalCacheWrite() == false)
        #expect(guardUnderTest.allowsLocalCacheWrite() == false)
        #expect(guardUnderTest.allowsLocalCacheWrite() == false)

        #expect(diagnostics.events.map(\.name) == ["firestore_low_disk_mode"])
        #expect(diagnostics.events.first?.details["trigger"] == "read_gate")
        #expect(diagnostics.events.first?.details["cache_mode"] == "persistent")
        #expect(diagnostics.events.first?.details["free_bytes"] == "0")
        #expect(telemetry.records.map(\.name) == ["firestore_low_disk_mode"])
        #expect(telemetry.records.first?.parameters["trigger"] == .string("read_gate"))

        volume.freeBytes = Self.floor
        #expect(guardUnderTest.allowsLocalCacheWrite())
    }

    @Test
    func theKillSwitchOffLeavesTheSDKDefaultAndNeverRefuses() {
        let volume = ScriptedVolume(availableBytes: 0, importantUsageBytes: 0)
        let diagnostics = SpyDiagnosticsRecorder()
        let telemetry = RecordedTelemetry()
        let store = RemoteFeatureFlagStore(
            snapshot: .resolving(remoteValues: [RemoteFeatureFlag.firestoreMemoryCacheOnLowDisk.key: false])
        )
        let guardUnderTest = FirestoreDiskGuard(
            freeSpace: volume,
            featureFlags: store,
            diagnostics: diagnostics,
            telemetry: telemetry.track
        )

        let mode = guardUnderTest.decideCacheMode()

        #expect(mode == .persistent(sizeBytes: FirestoreDiskPolicy.sdkDefaultPersistentCacheSizeBytes))
        #expect(guardUnderTest.allowsLocalCacheWrite())
        #expect(diagnostics.events.isEmpty)
        #expect(telemetry.records.isEmpty)
    }

    /// The gate reads the switch live, so an operator can disarm it on a running fleet.
    @Test
    func flippingTheSwitchOffMidSessionDisarmsTheGate() {
        let volume = ScriptedVolume(availableBytes: 0, importantUsageBytes: nil)
        let store = RemoteFeatureFlagStore()
        let guardUnderTest = FirestoreDiskGuard(
            freeSpace: volume,
            featureFlags: store,
            diagnostics: SpyDiagnosticsRecorder(),
            telemetry: { _ in }
        )
        // Activated while the volume still had room, then the volume filled.
        volume.freeBytes = Self.floor
        guardUnderTest.decideCacheMode()
        volume.freeBytes = 0
        #expect(guardUnderTest.allowsLocalCacheWrite() == false)

        store.apply(.resolving(remoteValues: [RemoteFeatureFlag.firestoreMemoryCacheOnLowDisk.key: false]))

        #expect(guardUnderTest.allowsLocalCacheWrite())
    }

    @Test
    func theRealReaderAnswersForTheHostsVolume() throws {
        let reader = VolumeFreeSpaceReader()
        let available = try #require(reader.availableBytes())
        #expect(available > 0)
        let important = try #require(reader.availableBytesForImportantUsage())
        #expect(important >= available)
    }

    @Test
    func theRealReaderSaysNilForAPathThatDoesNotExist() {
        let reader = VolumeFreeSpaceReader(path: "/nonexistent/\(UUID().uuidString)")
        #expect(reader.availableBytes() == nil)
    }
}

/// A volume whose free space the test sets.
final class ScriptedVolume: VolumeFreeSpaceReading, @unchecked Sendable {
    private let lock = NSLock()
    private var _availableBytes: Int64?
    private var _importantUsageBytes: Int64?

    init(availableBytes: Int64?, importantUsageBytes: Int64?) {
        _availableBytes = availableBytes
        _importantUsageBytes = importantUsageBytes
    }

    /// Set by a test to move the volume between states.
    var freeBytes: Int64? {
        get { lock.withLock { _availableBytes } }
        set { lock.withLock { _availableBytes = newValue } }
    }

    func availableBytes() -> Int64? {
        lock.withLock { _availableBytes }
    }

    func availableBytesForImportantUsage() -> Int64? {
        lock.withLock { _importantUsageBytes }
    }
}

/// The telemetry records a guard handed to the facade.
final class RecordedTelemetry: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [TelemetryRecord] = []

    var records: [TelemetryRecord] { lock.withLock { recorded } }

    @Sendable
    func track(_ record: TelemetryRecord) {
        lock.withLock { recorded.append(record) }
    }
}
