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

    private let db = Firestore.firestore()
    private let appVersion: String

    init(appVersion: String = TelemetryBuildMetadata.current.appVersion) {
        self.appVersion = appVersion
    }

    func publish(_ heartbeat: AttemptHeartbeat, userId: String) async throws {
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
