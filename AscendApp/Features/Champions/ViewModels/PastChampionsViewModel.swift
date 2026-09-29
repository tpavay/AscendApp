import Foundation
import Observation

/// Past champions are past boards: a board frozen at one period's final result, stepped
/// back a period at a time.
///
/// Every board it shows is the finalizer's record - the podium and rows are the frozen
/// placings, never today's `leaderboard_stats` - so a past board can never re-rank.
@MainActor
@Observable
final class PastChampionsViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        /// Nothing has been finalized for this period (it has not closed, or predates results).
        case missing
        case failed
    }

    /// How many ranked rows a past board draws - the same top 100 the finalizer awards.
    static let rowLimit = 100

    static let timeFrames: [LeaderboardTimeFrame] = [.weekly, .monthly, .yearly]

    /// What decides how the board's climbers are shown: who is looking, and whom they block.
    struct ModerationInputs: Equatable {
        var viewerId: String?
        var blockedUserIds: Set<String> = []
        var isBlockListHydrated = false
    }

    private(set) var selectedTimeFrame: LeaderboardTimeFrame
    private(set) var period: LeaderboardPeriod?
    private(set) var result: LeaderboardResult?
    private(set) var placings: [LeaderboardPlacing] = []
    private(set) var mostClimbsPlacings: [LeaderboardPlacing] = []
    private(set) var state: LoadState = .loading
    private(set) var canGoBack = false
    /// The board's rows, moderated once per load or block-list change rather than per render.
    private(set) var entries: [ModeratedLeaderboardEntry] = []
    private(set) var mostClimbsEntries: [ModeratedLeaderboardEntry] = []

    @ObservationIgnored private let repository: any LeaderboardResultsReading
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var loadGeneration: UInt64 = 0
    @ObservationIgnored private var moderationInputs = ModerationInputs()

    init(
        timeFrame: LeaderboardTimeFrame = .weekly,
        repository: any LeaderboardResultsReading = LeaderboardResultsRepository.shared,
        now: @escaping () -> Date = { .now }
    ) {
        selectedTimeFrame = Self.timeFrames.contains(timeFrame) ? timeFrame : .weekly
        self.repository = repository
        self.now = now
    }

    /// The most recent period this frame has closed - where the stepper starts.
    var latestPeriod: LeaderboardPeriod? {
        selectedTimeFrame.previousPeriod(referenceDate: now())
    }

    var canGoForward: Bool {
        guard let period, let latestPeriod else { return false }
        return period.startAt < latestPeriod.startAt
    }

    var awardedTitle: ChampionTitle? {
        ChampionTitle(timeFrame: selectedTimeFrame)
    }

    func updateModeration(_ inputs: ModerationInputs) {
        guard inputs != moderationInputs else { return }
        moderationInputs = inputs
        moderateEntries()
    }

    func load() async {
        guard period == nil else { return }
        await show(latestPeriod)
    }

    func select(_ timeFrame: LeaderboardTimeFrame) async {
        guard timeFrame != selectedTimeFrame, Self.timeFrames.contains(timeFrame) else { return }
        selectedTimeFrame = timeFrame
        await show(latestPeriod)
    }

    func stepBack() async {
        guard canGoBack, let previous = period?.previous else { return }
        await show(previous)
    }

    func stepForward() async {
        guard canGoForward, let next = period?.next else { return }
        await show(next)
    }

    func retry() async {
        await show(period ?? latestPeriod)
    }

    private func show(_ period: LeaderboardPeriod?) async {
        loadGeneration &+= 1
        let generation = loadGeneration
        self.period = period
        result = nil
        placings = []
        mostClimbsPlacings = []
        moderateEntries()
        canGoBack = false
        state = .loading

        guard let period else {
            state = .missing
            return
        }

        do {
            async let loadedResult = repository.fetchResult(
                timeFrame: period.timeFrame,
                periodKey: period.key
            )
            async let previousResult = previousExists(before: period)
            let result = try await loadedResult
            let hasPrevious = await previousResult
            guard generation == loadGeneration else { return }

            canGoBack = hasPrevious
            guard let result else {
                state = .missing
                return
            }

            let placings = try await repository.fetchPlacings(
                resultID: result.id,
                limit: Self.rowLimit
            )
            let rankedIds = Set(placings.map(\.userId))
            let outsideMostClimbs = (result.mostClimbs?.userIds ?? []).filter { !rankedIds.contains($0) }
            let extraPlacings = try await repository.fetchPlacings(
                resultID: result.id,
                userIds: outsideMostClimbs
            )
            guard generation == loadGeneration else { return }

            self.result = result
            self.placings = placings
            let byUser = Dictionary(
                (placings + extraPlacings).map { ($0.userId, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            mostClimbsPlacings = (result.mostClimbs?.userIds ?? []).compactMap { byUser[$0] }
            moderateEntries()
            state = .loaded
        } catch {
            guard generation == loadGeneration else { return }
            state = .failed
        }
    }

    private func moderateEntries() {
        entries = moderated(placings)
        mostClimbsEntries = moderated(mostClimbsPlacings)
    }

    private func moderated(_ placings: [LeaderboardPlacing]) -> [ModeratedLeaderboardEntry] {
        let inputs = moderationInputs
        return placings.entries(currentUserId: inputs.viewerId).map {
            CrossUserIdentityAdapter.leaderboardEntry(
                $0,
                blockedUserIds: inputs.blockedUserIds,
                isBlockListHydrated: inputs.isBlockListHydrated
            )
        }
    }

    private func previousExists(before period: LeaderboardPeriod) async -> Bool {
        guard let previous = period.previous else { return false }
        return (try? await repository.fetchResult(
            timeFrame: previous.timeFrame,
            periodKey: previous.key
        )) != nil
    }
}
