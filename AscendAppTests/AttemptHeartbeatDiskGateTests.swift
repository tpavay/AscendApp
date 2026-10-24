import FirebaseCore
import FirebaseFirestore
import Foundation
import Testing
@testable import AscendApp

/// A heartbeat of a persistent-cache process on a volume at the floor is refused before the SDK
/// is asked.
///
/// The heartbeat exists to watch over a running climb, and it is one `setData(merge:)` a minute -
/// a LevelDB write before it is a network call. On a full volume that write is the commit
/// assertion that aborts the process, so the one report meant to notice a dead session would be
/// what killed it. The guard answers the same way it does for `ServerPreferredRead` and
/// `WorkoutSyncCoordinator`: refused, classified unreachable, recorded once.
struct AttemptHeartbeatDiskGateTests {
    @Test
    func aFullVolumeRefusesTheHeartbeatBeforeFirestoreIsAsked() async throws {
        try #require(FirebaseApp.app() != nil, "the test host configures Firebase at launch")
        // The kill switch off and room at launch - the persistent cache - then the volume fills.
        let volume = ScriptedVolume(availableBytes: FirestoreDiskPolicy.lowDiskFloorBytes * 2, importantUsageBytes: nil)
        let diagnostics = SpyDiagnosticsRecorder()
        let diskGuard = FirestoreDiskGuard(
            freeSpace: volume,
            featureFlags: .withMemoryCacheOff(),
            diagnostics: diagnostics,
            telemetry: { _ in }
        )
        diskGuard.decideCacheMode()
        volume.freeBytes = 0
        let repository = FirestoreAttemptHeartbeatRepository(
            db: Firestore.firestore(),
            diskGuard: diskGuard,
            appVersion: "1.2.3"
        )

        await #expect(throws: FirestoreLowDiskRefusal(availableBytes: 0)) {
            try await repository.publish(Self.openHeartbeat, userId: "user-123")
        }
        await #expect(throws: FirestoreLowDiskRefusal(availableBytes: 0)) {
            try await repository.publish(Self.openHeartbeat, userId: "user-123")
        }

        #expect(ServerReadFailureClass.classify(FirestoreLowDiskRefusal(availableBytes: 0)) == .unreachable)
        #expect(
            diagnostics.events.filter { $0.name == "firestore_low_disk_mode" }.count == 1,
            "the first refusal is the fact; the second heartbeat is the same fact"
        )
    }

    static let openHeartbeat = AttemptHeartbeat(
        sessionID: "session-1",
        mode: .justClimb,
        steps: 412,
        durationSeconds: 318,
        startedAt: Date(timeIntervalSince1970: 1_792_800_000),
        climbId: nil,
        state: .open,
        outcome: nil
    )
}
