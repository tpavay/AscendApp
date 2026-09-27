import Foundation
import Testing
@testable import AscendApp

/// Unseen recaps in memory, recording every `seenAt` write.
final class FakePeriodRecaps: PeriodRecapReading, @unchecked Sendable {
    var recaps: [PeriodRecap] = []
    private(set) var markedSeen: [[String]] = []

    func fetchUnseen(userId: String, limit: Int) async throws -> [PeriodRecap] {
        let seen = Set(markedSeen.flatMap { $0 })
        return Array(recaps.filter { !seen.contains($0.id) }.prefix(limit))
    }

    func markSeen(userId: String, recapIDs: [String]) async throws {
        markedSeen.append(recapIDs)
    }
}

@MainActor
@Suite(.serialized)
struct PeriodRecapCoordinatorTests {
    private static let now: Date = {
        var components = DateComponents(year: 2026, month: 9, day: 27, hour: 21)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    private let fixtures = ChampionRecapFixtures(viewerId: "me", now: Self.now)

    private func setUp() -> (FakePeriodRecaps, FakeLeaderboardResults, PeriodRecapLocalSeenStore) {
        let recaps = FakePeriodRecaps()
        let week = fixtures.periods().week
        recaps.recaps = [fixtures.recap(
            period: week,
            variant: .active,
            active: fixtures.active(rank: 3, climbers: 38, steps: 7_904, climbs: 5, awardRank: 3)
        )]
        let results = FakeLeaderboardResults()
        results.store(fixtures.weekBundle(period: week, viewerWins: false))
        let suite = "PeriodRecapCoordinatorTests.\(UUID().uuidString)"
        return (recaps, results, PeriodRecapLocalSeenStore(suiteName: suite))
    }

    @Test
    func anUnseenRecapBecomesAStoryAndClosingItMarksItSeenEverywhere() async throws {
        let (recaps, results, seenStore) = setUp()
        let coordinator = PeriodRecapCoordinator(recaps: recaps, results: results, seenStore: seenStore, isFeatureEnabled: { true })

        await coordinator.evaluate(userId: "me", modelContext: nil, now: Self.now)
        let story = try #require(coordinator.story)
        #expect(story.pages.count == 3)

        coordinator.dismiss()
        #expect(coordinator.story == nil)
        #expect(seenStore.seenIDs(userId: "me") == ["weekly_2026-W38"])
        try await Task.sleep(for: .milliseconds(50))
        #expect(recaps.markedSeen == [["weekly_2026-W38"]])

        // It never shows twice.
        await coordinator.evaluate(userId: "me", modelContext: nil, now: Self.now)
        #expect(coordinator.story == nil)
    }

    @Test
    func aRecapThisDeviceShowedIsResentNotReshown() async {
        let (recaps, results, seenStore) = setUp()
        seenStore.markSeen(userId: "me", recapIDs: ["weekly_2026-W38"])
        let coordinator = PeriodRecapCoordinator(recaps: recaps, results: results, seenStore: seenStore, isFeatureEnabled: { true })

        await coordinator.evaluate(userId: "me", modelContext: nil, now: Self.now)
        #expect(coordinator.story == nil)
        #expect(recaps.markedSeen == [["weekly_2026-W38"]])
    }

    @Test
    func theSwitchOffShowsNothingAndWritesNothing() async {
        let (recaps, results, seenStore) = setUp()
        let coordinator = PeriodRecapCoordinator(recaps: recaps, results: results, seenStore: seenStore, isFeatureEnabled: { false })

        await coordinator.evaluate(userId: "me", modelContext: nil, now: Self.now)
        #expect(coordinator.story == nil)
        #expect(recaps.markedSeen.isEmpty)
    }

    @Test
    func aResultThatFailsToLoadHoldsTheRecapForTheNextOpen() async {
        let (recaps, results, seenStore) = setUp()
        results.failsFor = ["weekly_2026-W38"]
        let coordinator = PeriodRecapCoordinator(recaps: recaps, results: results, seenStore: seenStore, isFeatureEnabled: { true })

        await coordinator.evaluate(userId: "me", modelContext: nil, now: Self.now)
        #expect(coordinator.story == nil)
        #expect(recaps.markedSeen.isEmpty)
        #expect(seenStore.seenIDs(userId: "me").isEmpty)
    }
}

/// The stored recap shape the compose step writes, read back.
struct PeriodRecapParserTests {
    @Test
    func anActiveRecapParsesItsNumbersAndAwards() throws {
        let data: [String: Any] = [
            "schemaVersion": 1,
            "cadence": "weekly",
            "periodKey": "2026-W38",
            "periodStartAt": Date(timeIntervalSince1970: 1_789_344_000),
            "periodEndAt": Date(timeIntervalSince1970: 1_789_948_800),
            "periodLabel": "Sep 14-20, 2026",
            "variant": "active",
            "active": [
                "rank": 3,
                "climberCount": 38,
                "percentileBand": "Top 10%",
                "climbs": 5,
                "steps": 12_480,
                "floors": 624,
                "previousClimbs": 3,
                "previousSteps": 9_380,
                "previousFloors": NSNull(),
                "awardRank": 3,
                "firstAscents": [["climbId": "tallinn", "name": "Tallinn TV Tower"], ["climbId": "x", "name": NSNull()]],
                "landmarksFinished": ["Tallinn TV Tower"]
            ],
            "inactive": NSNull(),
            "seenAt": NSNull()
        ]
        let recap = try #require(PeriodRecapParser.recap(id: "weekly_2026-W38", data: data))
        #expect(recap.variant == .active)
        #expect(recap.active?.rank == 3)
        #expect(recap.active?.previousSteps == 9_380)
        #expect(recap.active?.firstAscents == [PeriodRecap.FirstAscent(climbId: "tallinn", name: "Tallinn TV Tower")])
        #expect(recap.seenAt == nil)
        #expect(recap.resultID == "weekly_2026-W38")
    }

    @Test
    func aFieldOfOneCarriesNoRankAndNeverClimbedCarriesNoNumbers() throws {
        let base: [String: Any] = [
            "cadence": "monthly",
            "periodKey": "2026-M08",
            "periodStartAt": Date(timeIntervalSince1970: 1_785_542_400),
            "periodEndAt": Date(timeIntervalSince1970: 1_788_220_800)
        ]
        var solo = base
        solo["variant"] = "active"
        solo["active"] = ["rank": NSNull(), "climberCount": NSNull(), "climbs": 2, "steps": 900, "floors": 45]
        let recap = try #require(PeriodRecapParser.recap(id: "monthly_2026-M08", data: solo))
        #expect(recap.active?.rank == nil)
        #expect(recap.active?.climberCount == nil)

        var never = base
        never["variant"] = "never_climbed"
        let neverClimbed = try #require(PeriodRecapParser.recap(id: "monthly_2026-M08", data: never))
        #expect(neverClimbed.variant == .neverClimbed)
        #expect(neverClimbed.active == nil)

        var yearly = base
        yearly["cadence"] = "yearly"
        yearly["variant"] = "never_climbed"
        #expect(PeriodRecapParser.recap(id: "yearly_2026", data: yearly) == nil)
    }
}
