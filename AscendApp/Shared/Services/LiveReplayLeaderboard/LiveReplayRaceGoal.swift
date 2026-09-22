import Foundation

/// The goal a live session is run against, which on a Just Climb decides what
/// "best" means for every climber on the board.
///
/// Settled by the captain on 2026-09-22. A climber's previous best on a Just
/// Climb is not one stored fact but three, and the one the board draws follows
/// the goal set for *this* session: with no goal it is their most steps all
/// time; with a step goal it is their fastest run to that count, a longer climb
/// counting through its split; with a duration goal it is the run on which they
/// had the most steps within that time, a climb that ended earlier counting at
/// its final steps. Rivals' single row is chosen by the same rule, so a race is
/// still a field of climbers, one row per climber.
///
/// The server writes the answer onto every Just Climb entry: `isBestForUser`
/// for the open case, and `bestForGoals` - the goal keys the entry's attempt
/// wins - for the other two. The window filters on whichever this goal names.
/// The key spelling and the goal space are shared with
/// `functions/src/liveReplayRaceBest.ts` and pinned by
/// `SharedTestVectors/live-replay-race-best-vector.json`; a key the server
/// never wrote matches nothing, and the board would simply read as empty.
enum LiveReplayRaceGoal: Hashable, Codable, Sendable {
    /// An open session: the most steps, all time.
    case open
    /// A step target: the fastest run to reach it.
    case steps(Int)
    /// A time target: the most steps within it.
    case duration(seconds: Int)

    /// The `bestForGoals` element the race filters on, or nil for an open
    /// session, which filters on `isBestForUser` instead.
    var entryFilterKey: String? {
        switch self {
        case .open:
            return nil
        case .steps(let steps):
            return "steps:\(steps)"
        case .duration(let seconds):
            return "duration:\(seconds)"
        }
    }

    /// One spelling for every cache the repository keys on a board, so two
    /// sessions with different goals on the same board never share an answer.
    var cacheKey: String {
        entryFilterKey ?? "open"
    }
}
