import Foundation

/// How many climbers race beyond the pack on the stairs: everyone the place pill counts ahead of
/// the climber and behind them, less the climbers drawn there.
///
/// It reads the pill's own standing, so the two can never disagree: where the pill states no
/// place among other climbers - nobody else has finished, or the board has not answered - there
/// are no counts either.
struct MountainCrowdCounts: Equatable, Sendable {
    let ahead: Int
    let behind: Int

    init?(standing: LiveClimbStandingText, drawn: MountainPack.Drawn) {
        guard case .rank(let rank) = standing.standing, rank >= 1 else { return nil }
        let climbers = max(standing.rankTotal, rank)
        ahead = max(rank - 1 - drawn.ahead, 0)
        behind = max(climbers - rank - drawn.behind, 0)
    }
}
