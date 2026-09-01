import Foundation

protocol LiveReplayLeaderboardServicing: Sendable {
    func fetchSummary(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayLeaderboardSummary

    func fetchCompletionRank(
        context: LiveReplayLeaderboardContext,
        workoutId: String,
        completionDurationSeconds: TimeInterval,
        finalSteps: Int
    ) async throws -> LiveReplayCompletionRank

    func fetchCompletionRankSnapshot(
        context: LiveReplayLeaderboardContext,
        workoutId: String
    ) async throws -> LiveReplayCompletionRankSnapshot?

    func fetchPublishStatus(
        workoutId: String
    ) async throws -> LiveReplayPublishStatus?

    func fetchCurrentUserBestCompletion(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayCurrentUserCompletion?

    func fetchCurrentUserFinisherStatus(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayFinisherStatus?

    func fetchCompletionLeaderboard(
        context: LiveReplayLeaderboardContext,
        limit: Int,
        cursor: LiveReplayCompletionLeaderboardCursor?,
        forceRefresh: Bool
    ) async throws -> LiveReplayCompletionLeaderboard

    func refreshIfNeeded(
        context: LiveReplayLeaderboardContext,
        elapsedSeconds: Int,
        currentSteps: Int,
        force: Bool
    ) async throws -> LiveReplayLeaderboardWindow?
}

extension LiveReplayLeaderboardServicing {
    func fetchCompletionLeaderboard(
        context: LiveReplayLeaderboardContext,
        limit: Int
    ) async throws -> LiveReplayCompletionLeaderboard {
        try await fetchCompletionLeaderboard(
            context: context,
            limit: limit,
            cursor: nil,
            forceRefresh: false
        )
    }

    func fetchCompletionLeaderboard(
        context: LiveReplayLeaderboardContext,
        limit: Int,
        cursor: LiveReplayCompletionLeaderboardCursor?
    ) async throws -> LiveReplayCompletionLeaderboard {
        try await fetchCompletionLeaderboard(
            context: context,
            limit: limit,
            cursor: cursor,
            forceRefresh: false
        )
    }
}

actor LiveReplayLeaderboardService: LiveReplayLeaderboardServicing {
    static let shared = LiveReplayLeaderboardService(
        repository: FirestoreLiveReplayLeaderboardRepository.shared
    )

    private struct CompletionLeaderboardCache {
        var leaderboard: LiveReplayCompletionLeaderboard
        var fetchedAt: Date
    }

    private let repository: LiveReplayLeaderboardRepository
    private let minFetchInterval: TimeInterval
    private let rowsAhead: Int
    private let rowsBehind: Int
    private let fetchTimeoutSeconds: Double
    private let completionCacheTTL: TimeInterval
    private let now: @Sendable () -> Date

    private var lastFetchAtByContext: [String: Date] = [:]
    private var lastBucketByContext: [String: Int] = [:]
    private var completionCacheByContext: [String: CompletionLeaderboardCache] = [:]

    init(
        repository: LiveReplayLeaderboardRepository,
        minFetchInterval: TimeInterval = 5,
        rowsAhead: Int = 8,
        rowsBehind: Int = 8,
        fetchTimeoutSeconds: Double = 6,
        completionCacheTTL: TimeInterval = 300,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.minFetchInterval = max(minFetchInterval, 0)
        self.rowsAhead = max(rowsAhead, 0)
        self.rowsBehind = max(rowsBehind, 0)
        self.fetchTimeoutSeconds = max(fetchTimeoutSeconds, 1)
        self.completionCacheTTL = max(completionCacheTTL, 0)
        self.now = now
    }

    func fetchSummary(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayLeaderboardSummary {
        let repository = repository
        return try await withLiveReplayLeaderboardTimeout(seconds: fetchTimeoutSeconds) {
            try await repository.fetchSummary(context: context)
        }
    }

    func fetchCompletionRank(
        context: LiveReplayLeaderboardContext,
        workoutId: String,
        completionDurationSeconds: TimeInterval,
        finalSteps: Int
    ) async throws -> LiveReplayCompletionRank {
        let repository = repository
        return try await withLiveReplayLeaderboardTimeout(seconds: fetchTimeoutSeconds) {
            try await repository.fetchCompletionRank(
                context: context,
                workoutId: workoutId,
                completionDurationSeconds: completionDurationSeconds,
                finalSteps: finalSteps
            )
        }
    }

    func fetchCompletionRankSnapshot(
        context: LiveReplayLeaderboardContext,
        workoutId: String
    ) async throws -> LiveReplayCompletionRankSnapshot? {
        let repository = repository
        return try await withLiveReplayLeaderboardTimeout(seconds: fetchTimeoutSeconds) {
            try await repository.fetchCompletionRankSnapshot(
                context: context,
                workoutId: workoutId
            )
        }
    }

    func fetchPublishStatus(
        workoutId: String
    ) async throws -> LiveReplayPublishStatus? {
        try await repository.fetchPublishStatus(workoutId: workoutId)
    }

    func fetchCurrentUserBestCompletion(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayCurrentUserCompletion? {
        try await repository.fetchCurrentUserBestCompletion(context: context)
    }

    func fetchCurrentUserFinisherStatus(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayFinisherStatus? {
        let repository = repository
        return try await withLiveReplayLeaderboardTimeout(seconds: fetchTimeoutSeconds) {
            try await repository.fetchCurrentUserFinisherStatus(context: context)
        }
    }

    func fetchCompletionLeaderboard(
        context: LiveReplayLeaderboardContext,
        limit: Int,
        cursor: LiveReplayCompletionLeaderboardCursor?,
        forceRefresh: Bool = false
    ) async throws -> LiveReplayCompletionLeaderboard {
        let key = context.contextKey
        let currentDate = now()

        if cursor == nil,
           !forceRefresh,
           let cached = completionCacheByContext[key],
           currentDate.timeIntervalSince(cached.fetchedAt) < completionCacheTTL,
           cached.leaderboard.rows.count >= max(limit, 1) || !cached.leaderboard.hasMoreRows {
            return cached.leaderboard
        }

        let page = try await repository.fetchCompletionLeaderboard(
            context: context,
            limit: limit,
            cursor: cursor,
            forceRefresh: forceRefresh
        )

        if cursor != nil {
            let cachedLeaderboard = completionCacheByContext[key]?.leaderboard ?? .empty
            let mergedLeaderboard = cachedLeaderboard.appending(page)
            completionCacheByContext[key] = CompletionLeaderboardCache(
                leaderboard: mergedLeaderboard,
                fetchedAt: currentDate
            )
            return page
        }

        completionCacheByContext[key] = CompletionLeaderboardCache(
            leaderboard: page,
            fetchedAt: currentDate
        )
        return page
    }

    func refreshIfNeeded(
        context: LiveReplayLeaderboardContext,
        elapsedSeconds: Int,
        currentSteps: Int,
        force: Bool = false
    ) async throws -> LiveReplayLeaderboardWindow? {
        let bucketIndex = max(elapsedSeconds, 0) / context.bucketIntervalSeconds
        let key = context.contextKey
        let currentDate = now()

        if !force,
           lastBucketByContext[key] == bucketIndex,
           let lastFetchAt = lastFetchAtByContext[key],
           currentDate.timeIntervalSince(lastFetchAt) < minFetchInterval {
            return nil
        }

        let repository = repository
        let rowsAhead = rowsAhead
        let rowsBehind = rowsBehind
        let window = try await withLiveReplayLeaderboardTimeout(seconds: fetchTimeoutSeconds) {
            try await repository.fetchWindow(
                context: context,
                bucketIndex: bucketIndex,
                currentSteps: currentSteps,
                rowsAhead: rowsAhead,
                rowsBehind: rowsBehind
            )
        }

        lastBucketByContext[key] = bucketIndex
        lastFetchAtByContext[key] = currentDate
        return window
    }
}

private enum LiveReplayLeaderboardTimeoutError: LocalizedError {
    case operationTimedOut

    var errorDescription: String? {
        switch self {
        case .operationTimedOut:
            return "The live replay leaderboard request timed out."
        }
    }
}

/// Bounds a leaderboard read, and - because the group is structured - tears the read down when the
/// caller is cancelled. A screen that closes mid-fetch must not leave a request running to its
/// timeout: work that outlives its screen is wasted battery and a stale write waiting to happen.
private func withLiveReplayLeaderboardTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw LiveReplayLeaderboardTimeoutError.operationTimedOut
        }

        defer { group.cancelAll() }
        guard let result = try await group.next() else {
            throw LiveReplayLeaderboardTimeoutError.operationTimedOut
        }

        return result
    }
}
