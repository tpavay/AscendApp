import FirebaseFirestore
import Foundation
import Testing
@testable import AscendApp

/// The low-disk pre-flight on the one shared server-read path.
///
/// Every forced read is a Firestore listen, every listen is a LevelDB transaction, and on a
/// full volume that transaction's commit aborts the process. So when the guard says the volume
/// is at the floor, the read is refused before the SDK is asked - no attempt, no quiet retry
/// (there is no stream to wait for), no cache fallback (a cache read is a LevelDB transaction
/// too) - and the failure classifies as unreachable, which every caller already treats as
/// "no answer this time, keep going".
struct ServerPreferredReadDiskGateTests {
    @Test
    func aFullVolumeRefusesTheReadBeforeTheSDKIsAsked() async {
        let volume = ScriptedVolume(availableBytes: 0, importantUsageBytes: nil)
        let diskGuard = FirestoreDiskGuard(
            freeSpace: volume,
            featureFlags: RemoteFeatureFlagStore(),
            diagnostics: SpyDiagnosticsRecorder(),
            telemetry: { _ in }
        )
        diskGuard.decideCacheMode()
        // Decided as persistent while the volume had room, then it filled.
        volume.freeBytes = FirestoreDiskPolicy.lowDiskFloorBytes
        diskGuard.decideCacheMode()
        volume.freeBytes = 0
        let attempts = AttemptLog()

        let outcome = await ServerPreferredRead.run(
            policy: .cacheFallback,
            hasNetworkPath: { true },
            wait: { _ in attempts.noteWait() },
            diskGuard: diskGuard
        ) { attempt -> String in
            attempts.note(attempt)
            return "never"
        }

        #expect(attempts.attempts.isEmpty, "the SDK must not be asked at all")
        #expect(attempts.waits == 0, "a full volume is not a dropped stream; nothing two seconds can bring back")
        #expect(outcome.isFromCache == false)
        #expect(outcome.failures.map(\.failureClass) == [.unreachable])
        guard case .failure(let error) = outcome.result else {
            Issue.record("expected a refusal")
            return
        }
        #expect(error is FirestoreLowDiskRefusal)
        #expect(ServerReadFailureClass.classify(error) == .unreachable)
    }

    @Test
    func aMemoryCacheProcessReadsNormallyOnAFullVolume() async throws {
        let volume = ScriptedVolume(availableBytes: 0, importantUsageBytes: nil)
        let diskGuard = FirestoreDiskGuard(
            freeSpace: volume,
            featureFlags: RemoteFeatureFlagStore(),
            diagnostics: SpyDiagnosticsRecorder(),
            telemetry: { _ in }
        )
        #expect(diskGuard.decideCacheMode() == .memory)

        let value = try await ServerPreferredRead.serverRequired(diskGuard: diskGuard) { "server" }

        #expect(value == "server")
    }

    @Test
    func aVolumeWithRoomLeavesTheReadPathUntouched() async throws {
        let volume = ScriptedVolume(availableBytes: FirestoreDiskPolicy.lowDiskFloorBytes * 2, importantUsageBytes: nil)
        let diskGuard = FirestoreDiskGuard(
            freeSpace: volume,
            featureFlags: RemoteFeatureFlagStore(),
            diagnostics: SpyDiagnosticsRecorder(),
            telemetry: { _ in }
        )
        diskGuard.decideCacheMode()
        let attempts = AttemptLog()

        let outcome = await ServerPreferredRead.run(
            policy: .serverRequired,
            hasNetworkPath: { true },
            wait: { _ in },
            diskGuard: diskGuard
        ) { attempt -> String in
            attempts.note(attempt)
            return "server"
        }

        #expect(try outcome.result.get() == "server")
        #expect(attempts.attempts == [.server])
    }

    /// The volume fills between the failed server attempt and the cache fallback: the fallback
    /// is a LevelDB transaction too, so it is not consulted, and the caller gets the server's
    /// own failure rather than a stale copy.
    @Test
    func aVolumeThatFillsBeforeTheCacheFallbackSkipsTheFallback() async {
        let volume = ScriptedVolume(availableBytes: FirestoreDiskPolicy.lowDiskFloorBytes * 2, importantUsageBytes: nil)
        let diskGuard = FirestoreDiskGuard(
            freeSpace: volume,
            featureFlags: RemoteFeatureFlagStore(),
            diagnostics: SpyDiagnosticsRecorder(),
            telemetry: { _ in }
        )
        diskGuard.decideCacheMode()
        let attempts = AttemptLog()

        let outcome = await ServerPreferredRead.run(
            policy: ServerPreferredReadPolicy(retriesUnreachable: false, fallsBackToCache: true),
            hasNetworkPath: { true },
            wait: { _ in },
            diskGuard: diskGuard
        ) { attempt -> String in
            attempts.note(attempt)
            volume.freeBytes = 0
            throw Firestore.error(.unavailable)
        }

        #expect(attempts.attempts == [.server], "the cache was never read")
        #expect(outcome.isFromCache == false)
        #expect(outcome.failures.map(\.failureClass) == [.unreachable])
        #expect(Firestore.code(of: outcome.result) == FirestoreErrorCode.unavailable.rawValue)
    }

    @Test
    func theRefusalClassifiesAsUnreachable() {
        #expect(ServerReadFailureClass.classify(FirestoreLowDiskRefusal(availableBytes: 12)) == .unreachable)
        #expect(FirestoreLowDiskRefusal(availableBytes: 12).errorDescription?.contains("12") == true)
    }
}

private final class AttemptLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ServerPreferredReadAttempt] = []
    private var recordedWaits = 0

    var attempts: [ServerPreferredReadAttempt] { lock.withLock { recorded } }
    var waits: Int { lock.withLock { recordedWaits } }

    func note(_ attempt: ServerPreferredReadAttempt) {
        lock.withLock { recorded.append(attempt) }
    }

    func noteWait() {
        lock.withLock { recordedWaits += 1 }
    }
}
