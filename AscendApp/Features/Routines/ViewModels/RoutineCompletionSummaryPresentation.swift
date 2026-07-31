import Foundation

/// Ranking state and achievement copy for the routine completion summary. A session that forfeited
/// credit must not claim a completion or show a standing it will never hold.
struct RoutineCompletionSummaryPresentation: Equatable {
    /// Whether this session ranks anywhere. When it does not there is no ranking card at all - the
    /// achievement row already states the outcome, and a status word in the slot where a rank goes
    /// reads as a load that never finished.
    let ranksOnLeaderboard: Bool
    /// `nil` leaves the summary's own achievement copy in place. A forfeited session replaces it so
    /// the card cannot announce a completion the ranking card just denied.
    let achievementTitleOverride: String?
    let achievementIconNameOverride: String?

    init(stopReason: HeadphoneMotionSessionStopReason, hasRoutineLeaderboard: Bool) {
        guard stopReason.earnsCompetitiveCredit else {
            ranksOnLeaderboard = false
            achievementTitleOverride = "SESSION ENDED"
            achievementIconNameOverride = "clock.arrow.circlepath"
            return
        }

        ranksOnLeaderboard = hasRoutineLeaderboard
        achievementTitleOverride = nil
        achievementIconNameOverride = nil
    }
}
