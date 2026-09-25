import Foundation

/// The kind of session a Home today row stands for. Mirrors the `kind` field the
/// server writes on `home_today_activity/global`, so the raw values are the contract.
enum HomeTodayActivityKind: String, Sendable, CaseIterable {
    case liveClimb = "live_climb"
    case justClimb = "just_climb"
    case routineTemplate = "routine_template"
    case routine
}

/// The goal a Just Climb row was set to, in the server's own spelling.
enum HomeTodayJustClimbGoalKind: String, Sendable, CaseIterable {
    case open
    case duration
    case steps
}
