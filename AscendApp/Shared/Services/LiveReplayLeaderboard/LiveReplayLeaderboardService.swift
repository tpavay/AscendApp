import Foundation

protocol LiveReplayLeaderboardServicing: Sendable {
    func fetchSummary(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayLeaderboardSummary

    func refreshIfNeeded(
        context: LiveReplayLeaderboardContext,
        elapsedSeconds: Int,
        currentSteps: Int,
        force: Bool
    ) async throws -> LiveReplayLeaderboardWindow?
}

actor LiveReplayLeaderboardService: LiveReplayLeaderboardServicing {
    static let shared = LiveReplayLeaderboardService(
        repository: FirestoreLiveReplayLeaderboardRepository.shared
    )

    private let repository: LiveReplayLeaderboardRepository
    private let minFetchInterval: TimeInterval
    private let rowsAhead: Int
    private let rowsBehind: Int
    private let fetchTimeoutSeconds: Double
    private let now: @Sendable () -> Date

    private var lastFetchAtByContext: [String: Date] = [:]
    private var lastBucketByContext: [String: Int] = [:]

    init(
        repository: LiveReplayLeaderboardRepository,
        minFetchInterval: TimeInterval = 5,
        rowsAhead: Int = 8,
        rowsBehind: Int = 8,
        fetchTimeoutSeconds: Double = 6,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.minFetchInterval = max(minFetchInterval, 0)
        self.rowsAhead = max(rowsAhead, 0)
        self.rowsBehind = max(rowsBehind, 0)
        self.fetchTimeoutSeconds = max(fetchTimeoutSeconds, 1)
        self.now = now
    }

    func fetchSummary(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayLeaderboardSummary {
        try await repository.fetchSummary(context: context)
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

private func withLiveReplayLeaderboardTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let state = LiveReplayLeaderboardTimeoutContinuationState(continuation: continuation)

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
            await state.resume(with: .failure(LiveReplayLeaderboardTimeoutError.operationTimedOut))
        }
    }
}

private actor LiveReplayLeaderboardTimeoutContinuationState<T: Sendable> {
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
