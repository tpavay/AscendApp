import Foundation

enum LiveReplayLeaderboardContextType: String, Codable, Sendable {
    case liveClimb = "live_climb"
    case justClimb = "just_climb"
    case routineTemplate = "routine_template"
    case routine = "routine"
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
        targetSteps: Int,
        bucketIntervalSeconds: Int = 10
    ) -> LiveReplayLeaderboardContext {
        LiveReplayLeaderboardContext(
            type: .justClimb,
            id: "global",
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
