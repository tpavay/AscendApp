import Foundation

/// The climber's recorded answer to whether Ascend may email them.
///
/// "Never answered" is its own case on purpose. The gate used to read a missing
/// preference as a yes, which meant Ascend could not name a single climber who
/// had actually chosen to hear from it - and beehiiv's acceptable use policy
/// requires affirmative consent it can be asked to evidence. An answer nobody
/// gave is not permission, so `undecided` never allows a send.
enum LifecycleEmailConsent: Equatable, Sendable {
    /// Nobody has asked, or the answer never reached the server.
    case undecided
    case granted
    case declined

    /// Whether lifecycle email may be sent. Only an explicit yes qualifies.
    var allowsEmail: Bool {
        self == .granted
    }

    /// Whether a real choice is on record, however it went.
    var isDecided: Bool {
        self != .undecided
    }

    /// Reads the stored flag, where an absent flag means nobody ever answered.
    init(storedFlag: Bool?) {
        switch storedFlag {
        case .some(true):
            self = .granted
        case .some(false):
            self = .declined
        case .none:
            self = .undecided
        }
    }

    /// The answer a climber just gave.
    init(isGranted: Bool) {
        self = isGranted ? .granted : .declined
    }
}
