import Foundation

/// Copy and ranking state for the routine completion summary. A session that forfeited credit
/// must not claim a completion or show a standing it will never hold.
struct RoutineCompletionSummaryPresentation: Equatable {
    let rankingLabel: String
    /// The detail line under a routine's own in-session standing. The hero cannot name that
    /// bucket-windowed race population itself, so this states the session finished instead.
    let completedDetail: String
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
            rankingLabel = "ROUTINE"
            completedDetail = "SESSION ENDED"
            ranksOnLeaderboard = false
            achievementTitleOverride = "SESSION ENDED"
            achievementIconNameOverride = "clock.arrow.circlepath"
            return
        }

        rankingLabel = "ROUTINE RANK"
        completedDetail = "ROUTINE COMPLETE"
        ranksOnLeaderboard = hasRoutineLeaderboard
        achievementTitleOverride = nil
        achievementIconNameOverride = nil
    }
}
