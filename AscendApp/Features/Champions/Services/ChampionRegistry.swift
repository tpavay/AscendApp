import Foundation
import Observation

/// Who reigns right now: the weekly, monthly and yearly champions of the periods that
/// closed most recently.
///
/// Every picture of a climber reads its crown from here by uid (`ClimberAvatar`), so a
/// surface cannot forget the mark and a blocked climber keeps it on the placeholder -
/// a title is a standing, not identity. Until the finalizer has written a period's
/// result (the first 15 minutes after it closes) nobody reigns for that frame, rather
/// than the app guessing from live rows.
@MainActor
@Observable
final class ChampionRegistry {
    static let shared = ChampionRegistry()

    /// How long a successful read stays fresh before a foreground refresh re-reads it.
    static let freshness: TimeInterval = 10 * 60

    private(set) var reigns: [ChampionTitle: ChampionReign] = [:]
    private(set) var titlesByUserId: [String: ChampionTitles] = [:]

    /// Whether champion surfaces render at all, mirrored from `champion_recognition_enabled`
    /// so flipping the switch re-renders every crown on the next frame.
    private(set) var isEnabled: Bool

    @ObservationIgnored private let repository: any LeaderboardResultsReading
    @ObservationIgnored private let isFeatureEnabled: @MainActor () -> Bool
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private var lastRefreshAt: Date?
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var flagObserver: Task<Void, Never>?

    init(
        repository: any LeaderboardResultsReading = LeaderboardResultsRepository.shared,
        isFeatureEnabled: @escaping @MainActor () -> Bool = {
            RemoteFeatureFlagStore.shared.isEnabled(.championRecognition)
        },
        clock: @escaping @MainActor () -> Date = { .now }
    ) {
        self.repository = repository
        self.isFeatureEnabled = isFeatureEnabled
        self.clock = clock
        isEnabled = isFeatureEnabled()
        flagObserver = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .remoteFeatureFlagsDidChange) {
                self?.syncFeatureFlag()
            }
        }
    }

    func syncFeatureFlag() {
        let enabled = isFeatureEnabled()
        if enabled != isEnabled {
            isEnabled = enabled
        }
    }

    func titles(for userId: String?) -> ChampionTitles {
        guard isEnabled, let userId, !userId.isEmpty else { return .none }
        return titlesByUserId[userId] ?? .none
    }

    func reign(for timeFrame: LeaderboardTimeFrame) -> ChampionReign? {
        guard isEnabled, let title = ChampionTitle(timeFrame: timeFrame) else { return nil }
        return reigns[title]
    }

    /// Reads the reigning result for every frame. A frame that fails to load keeps its last
    /// known reign while that reign is still current, so an offline foreground never strips
    /// crowns the app already knew about.
    func refresh(now: Date? = nil) async {
        let now = now ?? clock()
        syncFeatureFlag()
        generation &+= 1
        let expected = generation
        let repository = repository

        let loaded = await withTaskGroup(of: (ChampionTitle, ReignLoad).self) { group in
            for title in ChampionTitle.allCases {
                group.addTask {
                    (title, await Self.loadReign(for: title, now: now, repository: repository))
                }
            }
            var results: [ChampionTitle: ReignLoad] = [:]
            for await (title, load) in group {
                results[title] = load
            }
            return results
        }

        guard expected == generation else { return }

        var next: [ChampionTitle: ChampionReign] = [:]
        var anyFailed = false
        for title in ChampionTitle.allCases {
            switch loaded[title] ?? .failed {
            case .loaded(let reign):
                if let reign { next[title] = reign }
            case .failed:
                anyFailed = true
                if let existing = reigns[title], existing.isCurrent(at: now) {
                    next[title] = existing
                }
            }
        }
        apply(next)
        lastRefreshAt = anyFailed ? nil : now
    }

    /// Re-reads when the last read is stale or a period rolled since, so crowns change
    /// hands on the first foreground after a board closes.
    func refreshIfStale(now: Date? = nil) async {
        let now = now ?? clock()
        let expired = reigns.values.contains { !$0.isCurrent(at: now) }
        if !expired,
           let lastRefreshAt,
           now.timeIntervalSince(lastRefreshAt) < Self.freshness,
           lastRefreshAt <= now {
            return
        }
        await refresh(now: now)
    }

    /// Signing out ends every read made for that session.
    func clear() {
        generation &+= 1
        lastRefreshAt = nil
        apply([:])
    }

    /// Installs reigns directly - for previews, evidence tests and the debug fixtures that
    /// render a crowned board without a backend.
    func apply(_ reigns: [ChampionTitle: ChampionReign]) {
        guard reigns != self.reigns else { return }
        self.reigns = reigns
        titlesByUserId = Self.titlesByUserId(for: reigns)
    }

    static func titlesByUserId(
        for reigns: [ChampionTitle: ChampionReign]
    ) -> [String: ChampionTitles] {
        var titles: [String: ChampionTitles] = [:]
        for (title, reign) in reigns {
            for userId in reign.result.championUserIds {
                titles[userId, default: .none] = titles[userId, default: .none].adding(title)
            }
        }
        return titles
    }

    private enum ReignLoad: Sendable {
        case loaded(ChampionReign?)
        case failed
    }

    nonisolated private static func loadReign(
        for title: ChampionTitle,
        now: Date,
        repository: any LeaderboardResultsReading
    ) async -> ReignLoad {
        guard let period = title.timeFrame.previousPeriod(referenceDate: now) else {
            return .loaded(nil)
        }
        do {
            guard let result = try await repository.fetchResult(
                timeFrame: title.timeFrame,
                periodKey: period.key
            ), result.hasChampion else {
                return .loaded(nil)
            }
            let champions = try await repository.fetchChampionPlacings(resultID: result.id)
            return .loaded(ChampionReign(title: title, result: result, champions: champions))
        } catch {
            return .failed
        }
    }
}
