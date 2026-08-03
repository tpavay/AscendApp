import Foundation

enum LiveReplayLeaderboardContextType: String, Codable, Sendable {
    case liveClimb = "live_climb"
    case justClimb = "just_climb"
    case routineTemplate = "routine_template"
    case routine = "routine"

    /// Mirrors `rankingMetric` in `functions/src/liveReplayLeaderboard.ts` so a
    /// client-displayed rank never contradicts the rank the server published.
    var rankingMetric: LiveReplayRankingMetric {
        switch self {
        case .liveClimb, .justClimb:
            return .fastestCompletion
        case .routineTemplate, .routine:
            return .mostSteps
        }
    }
}

/// How a replay context decides who is winning.
///
/// A climb fixes the step target and lets the clock vary, so the fastest run wins.
/// A routine inverts that: its intervals fix the clock, so every finisher spends the
/// same time and only the steps taken inside that window separate them. Ranking a
/// routine on duration would rank tracking jitter and reward the shortest session.
enum LiveReplayRankingMetric: Sendable {
    case fastestCompletion
    case mostSteps

    /// The entry field this metric orders on.
    var field: String {
        switch self {
        case .fastestCompletion:
            return "completionDurationSeconds"
        case .mostSteps:
            return "finalSteps"
        }
    }

    /// Whether a higher stored value ranks better.
    var ranksHighestFirst: Bool {
        self == .mostSteps
    }

    /// The primary number a row leads with on a static completion board.
    var rowEmphasis: LiveReplayRowEmphasis {
        switch self {
        case .fastestCompletion:
            return .duration
        case .mostSteps:
            return .steps
        }
    }
}

/// Which of a completion row's two numbers earns the headline slot. A board must lead
/// with the number it ranked on, or the ordering reads as broken.
enum LiveReplayRowEmphasis: Sendable {
    case duration
    case steps
}

struct LiveReplayLeaderboardContext: Hashable, Codable, Sendable {
    let type: LiveReplayLeaderboardContextType
    let id: String
    let targetSteps: Int
    let bucketIntervalSeconds: Int

    init(
        type: LiveReplayLeaderboardContextType,
        id: String,
        targetSteps: Int,
        bucketIntervalSeconds: Int = 10
    ) {
        self.type = type
        self.id = id
        self.targetSteps = max(targetSteps, 1)
        self.bucketIntervalSeconds = max(bucketIntervalSeconds, 1)
    }

    static func liveClimb(
        climbId: String,
        targetSteps: Int,
        bucketIntervalSeconds: Int = 10
    ) -> LiveReplayLeaderboardContext {
        LiveReplayLeaderboardContext(
            type: .liveClimb,
            id: climbId,
            targetSteps: targetSteps,
            bucketIntervalSeconds: bucketIntervalSeconds
        )
    }

    static func justClimbGlobal(
        targetSteps: Int = JustClimbGoal.defaultOpenStepScale,
        bucketIntervalSeconds: Int = 10
    ) -> LiveReplayLeaderboardContext {
        LiveReplayLeaderboardContext(
            type: .justClimb,
            id: "global",
            targetSteps: targetSteps,
            bucketIntervalSeconds: bucketIntervalSeconds
        )
    }

    static func routineTemplate(
        templateId: String,
        targetSteps: Int,
        bucketIntervalSeconds: Int = 10
    ) -> LiveReplayLeaderboardContext {
        LiveReplayLeaderboardContext(
            type: .routineTemplate,
            id: templateId,
            targetSteps: targetSteps,
            bucketIntervalSeconds: bucketIntervalSeconds
        )
    }

    static func routine(
        routineId: UUID,
        targetSteps: Int,
        bucketIntervalSeconds: Int = 10
    ) -> LiveReplayLeaderboardContext {
        LiveReplayLeaderboardContext(
            type: .routine,
            id: routineId.uuidString,
            targetSteps: targetSteps,
            bucketIntervalSeconds: bucketIntervalSeconds
        )
    }

    var contextKey: String {
        "\(type.rawValue)__\(sanitizedId)"
    }

    private var sanitizedId: String {
        String(id.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
                ? character
                : "_"
        })
    }
}
