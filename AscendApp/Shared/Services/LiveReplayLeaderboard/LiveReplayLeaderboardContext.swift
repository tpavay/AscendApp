import Foundation

enum LiveReplayLeaderboardContextType: String, CaseIterable, Codable, Sendable {
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

    /// Whether this context collapses a climber's repeat completions into one row.
    ///
    /// Per-climb and per-routine-template contexts do: a climb board reaches the
    /// same step target every time, so the fastest attempt is genuinely that
    /// climber's best; a routine board fixes the clock, so the highest-steps
    /// attempt is theirs. An open Just Climb session has no target, so its
    /// shortest attempt is the one the climber quit earliest rather than their
    /// best. Mirrors the server allowlist in `functions/src/liveReplayLeaderboard.ts`.
    var collapsesRepeatFinishers: Bool {
        switch self {
        case .liveClimb, .routineTemplate:
            return true
        case .justClimb, .routine:
            return false
        }
    }

    /// What one row of this context's field stands for, so a surface can name the
    /// population it counts rather than guess a noun that happens to fit a climb.
    ///
    /// This is the board's own population, and so also the one the server's
    /// frozen stamp counted: a stamp counts whatever the board it sits beside
    /// counts. A standing the client recomputes counts `recomputedFieldPopulation`
    /// instead, and the two deliberately differ where a board races attempts.
    var fieldPopulation: LiveReplayFieldPopulation {
        collapsesRepeatFinishers ? .climbers : .completions
    }

    /// What a standing the client recomputes counts on this board.
    ///
    /// Always climbers. A recomputed standing counts finisher documents - one
    /// per climber, maintained on every context type - so an open Just Climb
    /// ranks a climber against unique climbers at their best, never against the
    /// same rival's four runs. Settled by the captain on 2026-09-02: a board
    /// with 41 finishes from 16 climbers reads "6th of 16", never "13th of 16"
    /// and never "13th of 41".
    ///
    /// Deliberately not derived from `collapsesRepeatFinishers`. That predicate
    /// also mirrors the server's `isBestForUser` writes and its frozen-standing
    /// branch, so folding this into it would change the server's meaning by
    /// implication; what the client's own standing counts is stated separately.
    var recomputedFieldPopulation: LiveReplayFieldPopulation {
        .climbers
    }
}

/// Who a field of rows counts.
///
/// Two Ascend surfaces deliberately count different populations of the same climb:
/// a live race collapses a rival's repeat runs to their best, while the static
/// board keeps every completion. Both are correct and they disagree by design, so
/// every surface that shows a field size states which one it is counting.
enum LiveReplayFieldPopulation: Sendable {
    /// One row per climber, on their best completion.
    case climbers
    /// One row per completed attempt.
    case completions

    /// The field-size line a board pins beneath its rows, e.g. `27 CLIMBERS`.
    func fieldSizeLabel(count: Int) -> String {
        let noun = switch self {
        case .climbers:
            count == 1 ? "CLIMBER" : "CLIMBERS"
        case .completions:
            count == 1 ? "COMPLETION" : "COMPLETIONS"
        }

        return "\(count.formatted()) \(noun)"
    }
}

/// A field size and the population it counts, kept together.
///
/// A bare total is what let two correct boards read as a contradiction, so the
/// count is never carried without the noun that characterises it. A surface with
/// no field it can substantiate holds no value at all rather than a number it
/// would have to guess a population for.
struct LiveReplayFieldSize: Equatable, Sendable {
    let population: LiveReplayFieldPopulation
    let count: Int

    var label: String {
        population.fieldSizeLabel(count: count)
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

    /// The finisher field holding a climber's standing best on this metric.
    ///
    /// Mirrors `finisherBestMetric` in `functions/src/liveReplayLeaderboard.ts`.
    /// A finisher document carries only the metric its board ranks on, so a
    /// routine finisher never holds a "best duration" that would read as a time
    /// to beat on a board where every finisher spends the same time.
    var finisherBestField: String {
        switch self {
        case .fastestCompletion:
            return "bestCompletionDurationSeconds"
        case .mostSteps:
            return "bestFinalSteps"
        }
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
