import Foundation

enum LeaderboardRefreshPolicy {
    static let networkTimeoutSeconds = 10.0
}

enum LeaderboardTimeoutError: LocalizedError {
    case operationTimedOut

    var errorDescription: String? {
        switch self {
        case .operationTimedOut:
            return "The leaderboard request timed out."
        }
    }
}

enum LeaderboardNetworkIssue {
    case offline
    case slowConnection
    case other

    static func classify(_ error: Error) -> LeaderboardNetworkIssue {
        let nsError = error as NSError
        let offlineCodes = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorCannotConnectToHost,
            NSURLErrorCannotFindHost,
            NSURLErrorDNSLookupFailed
        ]
        let slowConnectionCodes = [
            NSURLErrorTimedOut,
            NSURLErrorNetworkConnectionLost
        ]

        if error is LeaderboardTimeoutError || slowConnectionCodes.contains(nsError.code) {
            return .slowConnection
        }

        if offlineCodes.contains(nsError.code) {
            return .offline
        }

        if nsError.domain == NSURLErrorDomain {
            return .slowConnection
        }

        return .other
    }
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
