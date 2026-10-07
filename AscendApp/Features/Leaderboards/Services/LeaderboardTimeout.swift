import Foundation

enum LeaderboardRefreshPolicy {
    static let networkTimeoutSeconds = 10.0
}

enum LeaderboardTimeoutError: LocalizedError, ServerReadTimeoutError {
    case operationTimedOut

    var errorDescription: String? {
        switch self {
        case .operationTimedOut:
            return "The leaderboard request timed out."
        }
    }
}

/// Why a leaderboard read did not return the server's standings, as the climber needs it told.
///
/// `offline` is the phone having no network path at all, which the app-wide offline affordance
/// already owns. The other three are `ServerReadFailureClass`, kept apart because they used to
/// share one sentence - "Showing cached data. Latest refresh failed." - whether rules had
/// refused the read (2026-09-25, a production outage) or the stream had dropped for a moment
/// (2026-10-03, nothing wrong).
enum LeaderboardNetworkIssue: Equatable, Sendable {
    case offline
    case unreachable
    case refused
    case unexpected

    private static let offlineCodes = [
        NSURLErrorNotConnectedToInternet,
        NSURLErrorCannotConnectToHost,
        NSURLErrorCannotFindHost,
        NSURLErrorDNSLookupFailed
    ]

    static func classify(_ error: Error) -> LeaderboardNetworkIssue {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, offlineCodes.contains(nsError.code) {
            return .offline
        }

        switch ServerReadFailureClass.classify(error) {
        case .unreachable: return .unreachable
        case .refused: return .refused
        case .unexpected: return .unexpected
        }
    }

    /// The line over a board that is on screen but not current. State, then command. `nil` for
    /// `offline`, which shows the offline affordance instead of a sentence.
    ///
    /// Never "cached data": that is how the app stores the board, not something a climber did or
    /// can act on.
    var staleBoardMessage: String? {
        switch self {
        case .offline:
            nil
        case .unreachable, .unexpected:
            "Leaderboard not updated. Pull to retry."
        case .refused:
            Self.accessUnconfirmedMessage
        }
    }

    /// The line under `Leaderboard stalled.` when there is no board to show at all.
    var emptyBoardMessage: String {
        switch self {
        case .offline:
            "You're offline. Pull to retry."
        case .unreachable:
            "Couldn't reach the leaderboard. Pull to retry."
        case .refused:
            Self.accessUnconfirmedMessage
        case .unexpected:
            "Couldn't load this leaderboard. Pull to retry."
        }
    }

    private static let accessUnconfirmedMessage = "Ascend couldn't confirm your access. Pull to retry."
}

func withLeaderboardTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let state = LeaderboardTimeoutContinuationState(continuation: continuation)

        let operationTask = Task {
            do {
                let value = try await operation()
                await state.resume(with: .success(value))
            } catch {
                await state.resume(with: .failure(error))
            }
        }

        Task {
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                return
            }

            operationTask.cancel()
            await state.resume(with: .failure(LeaderboardTimeoutError.operationTimedOut))
        }
    }
}

private actor LeaderboardTimeoutContinuationState<T: Sendable> {
    private var continuation: CheckedContinuation<T, Error>?
    private var hasResumed = false

    init(continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<T, Error>) {
        guard hasResumed == false, let continuation else { return }
        hasResumed = true
        self.continuation = nil
        continuation.resume(with: result)
    }
}
