import Foundation

/// The standing a saved climb's share card asserts.
///
/// A completed climb's rank is permanent competitive history, so the card publishes the standing
/// the server froze when the attempt published - never a position recomputed against the rows that
/// exist right now, which is a different measurement and would put a number on a shared image that
/// stops being true the next time somebody finishes. The rule binds every entry point, which is
/// why the completion summary forwards only its `.atCompletion` standing while its own hero keeps
/// showing where the climber stands today: the two are supposed to differ.
///
/// Read when the composer opens, not when the screen does. A screen that resolved eagerly charged
/// a Firestore document read to every open of every session the server may never rank, and the
/// composer adopts a standing that lands after it is on screen, so nothing is gained by opening
/// the read earlier.
///
/// This is not the second, disagreeing rank source #285 deleted from Workout Detail. That one
/// called `LiveReplayLeaderboardService.fetchCompletionRank`, a current-basis recomputation, and it
/// ran on every open. `CompletedClimbRankService` is the one read path for the frozen value: it
/// serves a stored snapshot synchronously and network-free, fetches
/// `completionSnapshots/{workoutId}` at most once per workout per install, coalesces concurrent
/// callers, and never overwrites a frozen record. The completion summary reads the same service and
/// the same document, so the two surfaces cannot disagree.
struct SavedClimbShareStanding: Equatable {
    let rank: Int
    let totalClimbers: Int

    /// Nil for a workout the server has not ranked, and only for that: a snapshot that exists
    /// already carries a positive rank and field size, which `LiveReplayCompletionRankSnapshot`
    /// guarantees. Both halves come from the one document, so the card can never show a frozen
    /// position over a live field size.
    init?(snapshot: LiveReplayCompletionRankSnapshot?) {
        guard let snapshot else { return nil }
        self.rank = snapshot.rank
        self.totalClimbers = snapshot.completedCount
    }

    /// The frozen standing for this workout, reading the server snapshot only if this device has
    /// never held it.
    @MainActor
    static func resolve(
        context: LiveReplayLeaderboardContext,
        workoutId: String,
        service: CompletedClimbRankService = .shared
    ) async -> Self? {
        Self(snapshot: await service.resolveFrozenRank(context: context, workoutId: workoutId))
    }
}
