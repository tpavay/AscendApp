import Foundation

/// What the Log a climb screen is allowed to do with what has been typed.
///
/// The one decision that runs at save time. `ready` carries the pace verdict so the screen can say
/// up front that a climb will save but stay off the leaderboards, instead of letting a climber
/// find out from a missing row.
enum LoggedClimbValidation: Equatable, Sendable {
    /// Steps or time is still missing. Save stays disabled and nothing is said: an empty field is
    /// not a mistake.
    case incomplete
    /// Something typed cannot be saved. Save stays disabled and `Refusal.message` says why.
    case refused(Refusal)
    /// The climb can be saved. The verdict is `.withinCeiling` or `.aboveCeiling`, never `.absurd`.
    case ready(ClimbPacePolicy.Verdict)

    enum Refusal: Equatable, Sendable {
        case timeNotReal
        case impossiblePace(stepsPerMinute: Int)
        case tooManySteps
        case tooLong
        case startsInTheFuture

        var message: String {
            switch self {
            case .timeNotReal:
                return "Seconds run 00 to 59. Check the time."
            case .impossiblePace(let stepsPerMinute):
                return "That's \(stepsPerMinute.formatted()) steps a minute. Check the steps or time."
            case .tooManySteps:
                let limit = ClimbPacePolicy.maximumSteps.formatted()
                return "One climb holds up to \(limit) steps. Check the steps."
            case .tooLong:
                return "One climb runs up to 24 hours. Check the time."
            case .startsInTheFuture:
                return "A climb can't start in the future. Check the date."
            }
        }
    }

    /// Clock skew the start time is allowed before it reads as the future: a climber who picks
    /// "now" a few seconds before tapping Save has not logged a climb from tomorrow.
    static let futureTolerance: TimeInterval = 60

    static func validate(_ input: LoggedClimbInput, now: Date = Date()) -> LoggedClimbValidation {
        if !input.timeEntry.isValid {
            return .refused(.timeNotReal)
        }
        if input.date > now.addingTimeInterval(futureTolerance) {
            return .refused(.startsInTheFuture)
        }
        guard let steps = input.steps, let duration = input.duration else {
            return .incomplete
        }
        if steps > ClimbPacePolicy.maximumSteps {
            return .refused(.tooManySteps)
        }
        if duration > ClimbPacePolicy.maximumDuration {
            return .refused(.tooLong)
        }

        switch ClimbPacePolicy.verdict(steps: steps, duration: duration) {
        case .absurd(let stepsPerMinute):
            return .refused(.impossiblePace(stepsPerMinute: Int(stepsPerMinute.rounded())))
        case let verdict:
            return .ready(verdict)
        }
    }
}
