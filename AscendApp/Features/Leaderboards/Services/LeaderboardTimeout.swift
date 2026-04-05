import Foundation

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
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw LeaderboardTimeoutError.operationTimedOut
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
