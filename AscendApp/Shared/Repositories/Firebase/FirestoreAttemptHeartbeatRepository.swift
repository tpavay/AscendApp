import Foundation
@preconcurrency import FirebaseFirestore

/// Writes `users/{uid}/attempt_heartbeats/{sessionID}`.
///
/// Every write is a merge of the whole heartbeat, so a resumed session re-opens the same document
/// its first process was writing and the server sees one continuous record with a hole in it. The
/// server stamps `lastSeenAt` so a phone with a wrong clock cannot look alive or dead.
final class FirestoreAttemptHeartbeatRepository: AttemptHeartbeatPublishing, @unchecked Sendable {
    static let shared = FirestoreAttemptHeartbeatRepository()

    static let collectionName = "attempt_heartbeats"

    private let db: Firestore
    private let diskGuard: FirestoreDiskGuard
    private let appVersion: String

    init(
        db: Firestore = Firestore.firestore(),
        diskGuard: FirestoreDiskGuard = .shared,
        appVersion: String = TelemetryBuildMetadata.current.appVersion
    ) {
        self.db = db
        self.diskGuard = diskGuard
        self.appVersion = appVersion
    }

    func publish(_ heartbeat: AttemptHeartbeat, userId: String) async throws {
        // A heartbeat is a LevelDB write before it is a network call (`LocalStore::WriteLocally`),
        // and on a volume at the floor that commit aborts the process - in the middle of the one
        // activity the heartbeat exists to watch over. Refused here, the checkpointer records it
        // with the other publish failures and the climb keeps counting; a heartbeat is a report
        // about now, so nothing is queued (`docs/firestore-disk-full-guard.md`).
        if let refusal = diskGuard.localCacheWriteRefusal() {
            throw refusal
        }
        try await db
            .collection("users")
            .document(userId)
            .collection(Self.collectionName)
            .document(heartbeat.sessionID)
            .setData(Self.document(for: heartbeat, appVersion: appVersion), merge: true)
    }

    /// The exact field set `firestore.rules` admits for this document. Keep the two in step: the
    /// rule is strict `hasOnly`, so a field added here without a rules change is a silent
    /// `PERMISSION_DENIED` on every heartbeat.
    static func document(for heartbeat: AttemptHeartbeat, appVersion: String) -> [String: Any] {
        var data: [String: Any] = [
            "schemaVersion": AttemptHeartbeat.schemaVersion,
            "sessionID": heartbeat.sessionID,
            "mode": heartbeat.mode.rawValue,
            "steps": max(heartbeat.steps, 0),
            "durationSeconds": max(heartbeat.durationSeconds, 0),
            "startedAt": Timestamp(date: heartbeat.startedAt),
            "lastSeenAt": FieldValue.serverTimestamp(),
            "state": heartbeat.state.rawValue,
            "appVersion": appVersion
        ]
        data["climbId"] = heartbeat.climbId ?? NSNull()
        switch heartbeat.state {
        case .open:
            data["endedAt"] = NSNull()
            data["outcome"] = NSNull()
        case .ended:
            data["endedAt"] = FieldValue.serverTimestamp()
            data["outcome"] = heartbeat.outcome?.rawValue ?? NSNull()
        }
        return data
    }
}
