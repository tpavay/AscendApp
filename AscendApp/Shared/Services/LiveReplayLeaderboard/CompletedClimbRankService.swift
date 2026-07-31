import Foundation

/// The one read path for a completed workout's frozen rank.
///
/// Every completed-climb surface asks here instead of fetching `completionSnapshots/{workoutId}`
/// itself, so a rank is fetched at most once per workout per install and every surface shows the
/// same number. Concurrent callers for the same workout share one request.
///
/// This is deliberately *not* on the live path: `LiveReplayLeaderboardService.refreshIfNeeded` and
/// the live climb leaderboard keep re-reading the server every bucket, because a race in progress
/// has no frozen answer yet.
@MainActor
final class CompletedClimbRankService {
    static let shared = CompletedClimbRankService()

    private let leaderboardService: LiveReplayLeaderboardServicing
    private let store: FrozenCompletionRankStore
    private var inFlightRequests: [String: Task<LiveReplayCompletionRankSnapshot?, Never>] = [:]

    init(
        leaderboardService: LiveReplayLeaderboardServicing = LiveReplayLeaderboardService.shared,
        store: FrozenCompletionRankStore = FrozenCompletionRankStore()
    ) {
        self.leaderboardService = leaderboardService
        self.store = store
    }

    /// The frozen rank if this device already has it. Synchronous and network-free, so a reopened
    /// summary can render the final number in its first frame with no loading state at all.
    func frozenRank(
        context: LiveReplayLeaderboardContext,
        workoutId: String
    ) -> LiveReplayCompletionRankSnapshot? {
        store.snapshot(contextKey: context.contextKey, workoutId: workoutId)
    }

    /// The frozen rank, fetching the server snapshot exactly once if it is not stored yet.
    ///
    /// Returns `nil` when the server has not ranked this workout: that is a genuinely unranked
    /// result, not a value to invent locally.
    func resolveFrozenRank(
        context: LiveReplayLeaderboardContext,
        workoutId: String
    ) async -> LiveReplayCompletionRankSnapshot? {
        if let stored = frozenRank(context: context, workoutId: workoutId) {
            return stored
        }

        let requestKey = "\(context.contextKey)|\(workoutId)"
        if let inFlight = inFlightRequests[requestKey] {
            return await inFlight.value
        }

        let leaderboardService = leaderboardService
        let store = store
        let contextKey = context.contextKey
        let request = Task<LiveReplayCompletionRankSnapshot?, Never> {
            guard let fetched = try? await leaderboardService.fetchCompletionRankSnapshot(
                context: context,
                workoutId: workoutId
            ) else {
                return nil
            }

            return store.freeze(fetched, contextKey: contextKey)
        }

        inFlightRequests[requestKey] = request
        let snapshot = await request.value
        inFlightRequests[requestKey] = nil
        return snapshot
    }
}
