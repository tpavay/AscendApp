import Foundation

enum ModerationSource: String, Sendable {
    case globalLeaderboard = "global_leaderboard"
    case liveReplay = "live_replay"
    case completionLeaderboard = "completion_leaderboard"
    case communityAvatars = "community_avatars"
    case firstAscent = "first_ascent"
    case profile
}
