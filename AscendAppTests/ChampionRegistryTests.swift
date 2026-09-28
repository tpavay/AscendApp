import Foundation
import Testing
@testable import AscendApp

/// A results store in memory, keyed by result id.
final class FakeLeaderboardResults: LeaderboardResultsReading, @unchecked Sendable {
    var results: [String: LeaderboardResult] = [:]
    var placings: [String: [LeaderboardPlacing]] = [:]
    /// Mutated only between reads, never while a refresh is in flight.
    var failsFor: Set<String> = []

    func fetchResult(timeFrame: LeaderboardTimeFrame, periodKey: String) async throws -> LeaderboardResult? {
        let id = LeaderboardResult.documentID(timeFrame: timeFrame, periodKey: periodKey)
        if failsFor.contains(id) { throw URLError(.notConnectedToInternet) }
        return results[id]
    }

    func fetchPlacings(resultID: String, limit: Int) async throws -> [LeaderboardPlacing] {
        Array((placings[resultID] ?? []).sorted { $0.rank < $1.rank }.prefix(limit))
    }

    func fetchChampionPlacings(resultID: String) async throws -> [LeaderboardPlacing] {
        (placings[resultID] ?? []).filter { $0.rank == 1 }
    }

    func fetchPlacings(resultID: String, userIds: [String]) async throws -> [LeaderboardPlacing] {
        (placings[resultID] ?? []).filter { userIds.contains($0.userId) }
    }

    /// The all-time board's current leaders.
    var allTimeLeaders: [LeaderboardPlacing] = []

    func fetchAllTimeLeaders() async throws -> [LeaderboardPlacing] {
        if failsFor.contains("all_time") { throw URLError(.notConnectedToInternet) }
        return allTimeLeaders
    }

    func store(_ bundle: PeriodRecapResultBundle) {
        results[bundle.result.id] = bundle.result
        placings[bundle.result.id] = bundle.placings
    }
}

@MainActor
struct ChampionRegistryTests {
    private static let now: Date = {
        var components = DateComponents(year: 2026, month: 9, day: 27, hour: 21)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    private let fixtures = ChampionRecapFixtures(viewerId: "me", now: Self.now)

    private func store(crowning viewerWins: Bool) -> FakeLeaderboardResults {
        let store = FakeLeaderboardResults()
        let (week, month) = fixtures.periods()
        store.store(fixtures.weekBundle(period: week, viewerWins: viewerWins))
        store.store(fixtures.monthBundle(period: month))
        return store
    }

    @Test
    func theReigningChampionsAreThePreviousPeriodsNumberOnes() async {
        let registry = ChampionRegistry(repository: store(crowning: true), isFeatureEnabled: { true })
        await registry.refresh(now: Self.now)

        #expect(registry.titles(for: "me") == ChampionTitles([.weekly]))
        #expect(registry.titles(for: "fixture-ezra") == ChampionTitles([.monthly]))
        #expect(registry.titles(for: "fixture-maya") == .none)
        #expect(registry.reign(for: .weekly)?.result.period.key == "2026-W38")
        #expect(registry.reign(for: .yearly) == nil)
        #expect(registry.reign(for: .allTime) == nil)
    }

    @Test
    func turningTheSwitchOffHidesEveryCrownWithoutForgettingThem() async {
        var enabled = true
        let registry = ChampionRegistry(repository: store(crowning: true), isFeatureEnabled: { enabled })
        await registry.refresh(now: Self.now)
        #expect(!registry.titles(for: "me").isEmpty)

        enabled = false
        registry.syncFeatureFlag()
        #expect(registry.titles(for: "me").isEmpty)
        #expect(registry.reign(for: .weekly) == nil)

        enabled = true
        registry.syncFeatureFlag()
        #expect(registry.titles(for: "me") == ChampionTitles([.weekly]))
    }

    @Test
    func aFailedReadKeepsACurrentReignRatherThanStrippingTheCrown() async {
        let results = store(crowning: true)
        let registry = ChampionRegistry(repository: results, isFeatureEnabled: { true })
        await registry.refresh(now: Self.now)

        results.failsFor = ["weekly_2026-W38"]
        await registry.refresh(now: Self.now)
        #expect(registry.titles(for: "me") == ChampionTitles([.weekly]))
    }

    @Test
    func aReignEndsWhenTheNextPeriodCloses() async {
        let results = store(crowning: true)
        let registry = ChampionRegistry(repository: results, isFeatureEnabled: { true })
        await registry.refresh(now: Self.now)

        // A week later, week 39 has closed but its result has not landed: nobody reigns
        // rather than week 38's champion lingering.
        let nextWeek = Self.now.addingTimeInterval(7 * 86_400)
        #expect(registry.reign(for: .weekly)?.isCurrent(at: nextWeek) == false)
        await registry.refreshIfStale(now: nextWeek)
        #expect(registry.titles(for: "me").isEmpty)
    }

    @Test
    func theAllTimeCrownIsLiveOnWhoeverLeadsTheAllTimeBoard() async {
        let results = store(crowning: false)
        results.allTimeLeaders = [
            fixtures.placing(3, rank: 1, steps: 120_000, climbs: 80),
            fixtures.placing(4, rank: 1, steps: 120_000, climbs: 61)
        ]
        let registry = ChampionRegistry(repository: results, isFeatureEnabled: { true })
        await registry.refresh(now: Self.now)

        #expect(registry.titles(for: "fixture-ezra") == ChampionTitles([.monthly, .allTime]))
        #expect(registry.titles(for: "fixture-vera") == ChampionTitles([.allTime]))
        #expect(registry.reign(for: .allTime)?.isCurrent(at: Self.now.addingTimeInterval(400 * 86_400)) == true)
        #expect(registry.reign(for: .allTime)?.endsAt == nil)
    }

    @Test
    func theSignedInClimbersOwnRowIsCrownedWithoutAUid() async {
        let registry = ChampionRegistry(repository: store(crowning: true), isFeatureEnabled: { true })
        await registry.refresh(now: Self.now)
        registry.setCurrentUser("me")

        #expect(registry.titles(for: nil, isCurrentUser: true) == ChampionTitles([.weekly]))
        #expect(registry.titles(for: nil, isCurrentUser: false) == .none)
    }

    @Test
    func signingOutClearsEveryCrown() async {
        let registry = ChampionRegistry(repository: store(crowning: true), isFeatureEnabled: { true })
        await registry.refresh(now: Self.now)
        registry.clear()
        #expect(registry.titlesByUserId.isEmpty)
        #expect(registry.reigns.isEmpty)
    }
}

@MainActor
struct PastChampionsViewModelTests {
    private static let now: Date = {
        var components = DateComponents(year: 2026, month: 9, day: 27, hour: 21)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    private let fixtures = ChampionRecapFixtures(viewerId: "me", now: Self.now)

    @Test
    func theStepperStartsAtTheLatestClosedPeriodAndWalksBack() async {
        let results = FakeLeaderboardResults()
        var period = fixtures.periods().week
        for _ in 0..<3 {
            results.store(fixtures.weekBundle(period: period, viewerWins: false))
            period = period.previous!
        }
        let viewModel = PastChampionsViewModel(timeFrame: .weekly, repository: results, now: { Self.now })

        await viewModel.load()
        #expect(viewModel.period?.key == "2026-W38")
        #expect(viewModel.state == .loaded)
        #expect(viewModel.placings.first?.rank == 1)
        #expect(viewModel.mostClimbsPlacings.map(\.userId) == ["fixture-ezra"])
        #expect(viewModel.canGoBack)
        #expect(!viewModel.canGoForward)

        await viewModel.stepBack()
        #expect(viewModel.period?.key == "2026-W37")
        #expect(viewModel.canGoForward)

        await viewModel.stepBack()
        #expect(viewModel.period?.key == "2026-W36")
        #expect(!viewModel.canGoBack)

        await viewModel.select(.monthly)
        #expect(viewModel.period?.key == "2026-M08")
        #expect(viewModel.state == .missing)
    }
}

/// A block list with nobody on it, so a hydrated store shows every climber's real name.
actor NoBlocksModerationRepository: ModerationRepositoryProtocol {
    func fetchBlockedClimbers(blockerUserId: String, source: BlockListReadSource) async throws -> [BlockedClimber] {
        []
    }

    func block(blockerUserId: String, blockedUserId: String) async throws {}

    func unblock(blockerUserId: String, blockedUserId: String) async throws {}

    func submitReport(
        reporterUserId: String,
        reportedUserId: String,
        reason: ModerationReportReason,
        source: ModerationSource
    ) async throws {}
}
