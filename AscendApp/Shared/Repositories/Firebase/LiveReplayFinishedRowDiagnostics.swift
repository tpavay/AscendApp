import Foundation

/// Which swallowed finished-row read a diagnostic is about.
///
/// The finished half of the live window is read through two queries that each
/// need their own composite index, so a missing one degrades exactly one of
/// them. Naming the read keeps the report specific enough to act on.
enum LiveReplayFinishedRowRead: String, Sendable, CaseIterable {
    case aheadFetch = "live_replay_finished_rows_ahead_fetch_failed"
    case behindFetch = "live_replay_finished_rows_behind_fetch_failed"
    case aheadCount = "live_replay_finished_rows_ahead_count_failed"
    case ownGhost = "live_replay_own_ghost_read_failed"
    case ownClimbPlacing = "live_replay_own_climb_placing_read_failed"
}

/// Bounds the finished-row failure report to once per read per session.
///
/// The failure these reads swallow is deliberate - a missing index costs the
/// rivals already home rather than failing the whole board mid-climb - but the
/// swallow makes it indistinguishable from an empty finished field, so it has to
/// be reported. `fetchWindow` runs on a ~10s bucket clock and can be forced far
/// more often during a race, and an unbounded `recordError` is the Fatal App
/// Hang hazard that is production's top signal, so the first failure of each
/// read is the whole budget: the condition is a deployment fact, not an event,
/// and the second occurrence carries no information the first did not.
struct LiveReplayFinishedRowDiagnostics: Sendable {
    private var reported: Set<LiveReplayFinishedRowRead> = []

    mutating func shouldReport(_ read: LiveReplayFinishedRowRead) -> Bool {
        reported.insert(read).inserted
    }
}
