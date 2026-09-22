import Foundation

enum JustClimbGoalKind: String, CaseIterable, Identifiable {
    case open
    case duration
    case steps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open:
            return "No Goal"
        case .duration:
            return "Duration"
        case .steps:
            return "Steps"
        }
    }
}

struct JustClimbGoal: Identifiable, Equatable, Hashable {
    static let defaultDurationMinutes = 30
    static let defaultStepCount = 2_000
    static let minimumDurationMinutes = 5
    static let maximumDurationMinutes = 180
    static let minimumStepCount = 100
    static let maximumStepCount = 20_000
    /// The stepper increments on the setup sheet. Together with the bounds
    /// above they are the whole goal space, which is also exactly the set of
    /// goal keys the server writes onto Just Climb entries
    /// (`LiveReplayRaceGoal`), so a change here is a server change too.
    static let durationMinutesIncrement = 5
    static let stepCountIncrement = 100
    static let defaultOpenStepScale = 2_000

    let id: UUID
    var kind: JustClimbGoalKind
    var durationMinutes: Int
    var stepCount: Int

    init(
        id: UUID = UUID(),
        kind: JustClimbGoalKind = .open,
        durationMinutes: Int = Self.defaultDurationMinutes,
        stepCount: Int = Self.defaultStepCount
    ) {
        self.id = id
        self.kind = kind
        self.durationMinutes = min(
            max(durationMinutes, Self.minimumDurationMinutes),
            Self.maximumDurationMinutes
        )
        self.stepCount = min(
            max(stepCount, Self.minimumStepCount),
            Self.maximumStepCount
        )
    }

    var targetStepCount: Int? {
        kind == .steps ? stepCount : nil
    }

    var targetDuration: TimeInterval? {
        kind == .duration ? TimeInterval(durationMinutes * 60) : nil
    }

    /// What this goal makes "best" mean on the global Just Climb board, for the
    /// climber's own marker and for every rival's row.
    var raceGoal: LiveReplayRaceGoal {
        switch kind {
        case .open:
            return .open
        case .duration:
            return .duration(seconds: durationMinutes * 60)
        case .steps:
            return .steps(stepCount)
        }
    }

    var title: String {
        "Just Climb"
    }

    var subtitle: String {
        switch kind {
        case .open:
            return "Open session"
        case .duration:
            return "\(durationMinutes) min goal"
        case .steps:
            return "\(stepCount.formatted()) step goal"
        }
    }
}
