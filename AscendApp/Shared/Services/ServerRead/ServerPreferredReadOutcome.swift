import Foundation

/// What a server-preferred read ended with, and what it went through to get there.
struct ServerPreferredReadOutcome<Value> {
    /// The value read, or the error of the last server attempt when nothing could stand in.
    let result: Result<Value, any Error>
    /// True when the server gave no answer and `result` is the device's last copy. The value is
    /// then not current, and the caller owes the climber that honesty.
    let isFromCache: Bool
    /// Every server attempt that failed, in order. Empty when the first attempt answered.
    let failures: [ServerReadFailure]
    /// Whether the caller's refusal recovery ran. It runs at most once per read.
    let attemptedRefusalRecovery: Bool

    /// The server answered, but only after at least one failed attempt.
    var recoveredFromFailure: Bool {
        guard case .success = result else { return false }
        return !isFromCache && !failures.isEmpty
    }
}
