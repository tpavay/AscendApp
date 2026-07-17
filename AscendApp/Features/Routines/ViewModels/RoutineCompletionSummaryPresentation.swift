import Foundation

/// Copy and ranking state for the routine completion summary. A session that forfeited credit
/// must not claim a completion or show a standing it will never hold.
struct RoutineCompletionSummaryPresentation: Equatable {
    let rankingLabel: String
    let completedDetail: String
    let unrankedValueText: String
    let unrankedDetailText: String
    let showsPendingRankingState: Bool
    /// `nil` leaves the summary's own achievement copy in place. A forfeited session replaces it so
    /// the card cannot announce a completion the ranking card just denied.
    let achievementTitleOverride: String?
    let achievementIconNameOverride: String?

    init(stopReason: HeadphoneMotionSessionStopReason, hasRoutineLeaderboard: Bool) {
        guard stopReason.earnsCompetitiveCredit else {
            rankingLabel = "ROUTINE"
            completedDetail = "SESSION ENDED"
            unrankedValueText = "Incomplete"
            unrankedDetailText = "SESSION ENDED"
            showsPendingRankingState = false
            achievementTitleOverride = "SESSION ENDED"
            achievementIconNameOverride = "clock.arrow.circlepath"
            return
        }

        rankingLabel = hasRoutineLeaderboard ? "ROUTINE RANK" : "ROUTINE"
        completedDetail = "ROUTINE COMPLETE"
        unrankedValueText = "Complete"
        unrankedDetailText = "ROUTINE COMPLETE"
        showsPendingRankingState = hasRoutineLeaderboard
        achievementTitleOverride = nil
        achievementIconNameOverride = nil
    }
}
