import Foundation

/// One liveness report from a running headphone session, written to
/// `users/{uid}/attempt_heartbeats/{sessionID}` every `AttemptHeartbeatPolicy.interval`.
///
/// The device is the only place a session is counted, so until this existed a process that died
/// mid-climb left nothing anywhere: no event, no document, no log line for twenty minutes. A
/// scheduled Cloud Function (`flagStalledAttemptHeartbeats`) now flags any session whose heartbeat
/// stopped more than five minutes before it ended, which is how the captain learns about a lost
/// session within minutes rather than from the climber.
struct AttemptHeartbeat: Equatable, Sendable {
    enum State: String, Sendable {
        case open
        case ended
    }

    enum Outcome: String, Sendable {
        case saved
        case discarded
    }

    static let schemaVersion = 1

    let sessionID: String
    let mode: ActiveHeadphoneWorkoutDraftKind
    let steps: Int
    let durationSeconds: TimeInterval
    let startedAt: Date
    let climbId: String?
    let state: State
    let outcome: Outcome?
}

/// How often a heartbeat is written. Sixty seconds keeps a 20-minute climb at twenty tiny writes
/// while still placing a death inside a one-minute window.
enum AttemptHeartbeatPolicy {
    static let interval: TimeInterval = 60

    static func isDue(lastPublishedAt: Date?, now: Date) -> Bool {
        guard let lastPublishedAt else { return true }
        return now.timeIntervalSince(lastPublishedAt) >= interval
    }
}

/// The seam between the checkpointer and Firestore, so a session under test publishes to memory.
protocol AttemptHeartbeatPublishing: Sendable {
    func publish(_ heartbeat: AttemptHeartbeat, userId: String) async throws
}
