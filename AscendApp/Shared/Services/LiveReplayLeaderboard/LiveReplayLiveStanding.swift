import Foundation

/// Where the run on the machine places among the climber's own climbs of this
/// board, counting itself.
///
/// The race rows cannot answer this. They are collapsed to one row per climber,
/// so a climber's second-best run is not on the board at all - which is exactly
/// why a placing among their own history has to be counted from their own
/// entries rather than read off the field they are racing.
struct LiveReplayPersonalPlacing: Equatable, Sendable {
    let placing: Int
    let total: Int

    /// A climber standing on a board they have never finished. Their first run
    /// is first of one by construction, and no read is needed to know it.
    static let firstClimb = LiveReplayPersonalPlacing(placing: 1, total: 1)

    /// The population this placing counted, always named beside the number.
    var fieldLabel: String {
        "OF YOUR \(total.formatted()) CLIMB\(total == 1 ? "" : "S")"
    }

    var ordinalText: String {
        placing.rankOrdinalText
    }
}

/// What a live surface states about where the climber stands right now.
///
/// Two states and no third. Settled by the captain on 2026-09-02: every number
/// a live surface shows is labelled with the population it counted, so a bare
/// ordinal cannot be represented here at all. That is the whole point of the
/// type - a climber alone on a tower was being told `#1` with nothing on screen
/// naming what the one counted, seconds before the finish card told them the
/// truth, and the mid-climb-versus-finish disagreement is the defect this work
/// exists to remove.
///
/// The live panel and the Live Activity both resolve one of these, so whatever
/// the panel states the Lock Screen states.
enum LiveReplayLiveStanding: Equatable, Sendable {
    /// Other climbers have finished this board. The leaderboard placing leads,
    /// named by the field it was measured against, and the climber's own
    /// history is secondary beneath it.
    case racing(field: LiveReplayFieldSize?, ownClimbs: LiveReplayPersonalPlacing?)
    /// Nobody else has finished this board. There is no leaderboard placing to
    /// state and no field to name, so the climber's own climbs are the only
    /// population there is.
    case alone(ownClimbs: LiveReplayPersonalPlacing?)

    /// Whether a leaderboard placing may be drawn at all - in a row's rank cell,
    /// on the Lock Screen, anywhere.
    var showsLeaderboardRank: Bool {
        switch self {
        case .racing:
            return true
        case .alone:
            return false
        }
    }

    /// The field a leaderboard placing was measured against, where one exists.
    var field: LiveReplayFieldSize? {
        switch self {
        case .racing(let field, _):
            return field
        case .alone:
            return nil
        }
    }

    var ownClimbs: LiveReplayPersonalPlacing? {
        switch self {
        case .racing(_, let ownClimbs), .alone(let ownClimbs):
            return ownClimbs
        }
    }

    /// `isSoleClimber` is the board's own answer, never inferred from a missing
    /// field size: a routine board that cannot substantiate a count still has
    /// rivals on it, and treating "no count" as "nobody else" would strip the
    /// leaderboard placing off a board that has one.
    static func resolve(
        field: LiveReplayFieldSize?,
        ownClimbs: LiveReplayPersonalPlacing?,
        isSoleClimber: Bool
    ) -> LiveReplayLiveStanding {
        isSoleClimber
            ? .alone(ownClimbs: ownClimbs)
            : .racing(field: field, ownClimbs: ownClimbs)
    }
}
