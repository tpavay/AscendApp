import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Evidence for every page of every recap variant, photographed from the shipping
/// `PeriodRecapView` with its animations held at rest.
///
/// The stories come from `PeriodRecapStoryBuilder` through the same fixtures the Debug
/// preview plays, so what is photographed is what the builder decides. Copy is proved on
/// the accessibility tree; photographs land in `ASCEND_EVIDENCE_DIR` when it is set.
@MainActor
@Suite(.hostsAWindow)
struct PeriodRecapEvidenceTests {
    private static let now: Date = {
        var components = DateComponents(year: 2026, month: 9, day: 27, hour: 21)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    private let fixtures = ChampionRecapFixtures(viewerId: "viewer", viewerName: "Tyler Pavay", now: Self.now)

    @Test
    func theWeekIsEveryoneThenYoursThenTheCrown() async throws {
        try await photographEveryPage(of: .week, expecting: [
            ["everyone climbed.", "1,204,880", "climbers"],
            ["your week", "#3", "of 38 climbers · top 10%", "earned this week", "#3 finish", "first ascent", "new best efforts", "fastest 1,000 steps"],
            ["zoe ramirez took the crown.", "8,836 steps · 38 climbers", "most climbs", "take the crown", "past champions"]
        ])
    }

    @Test
    func theWinnerSeesTheirCoronation() async throws {
        try await photographEveryPage(of: .coronation, expecting: [
            ["everyone climbed."],
            ["#1", "champion"],
            ["you took the crown.", "your crown shows on your picture everywhere until", "defend it"]
        ])
    }

    @Test
    func anExactTieNamesBothChampions() async throws {
        try await photographEveryPage(of: .coChampions, expecting: [
            ["everyone climbed."],
            ["your week"],
            ["zoe ramirez & noah grant took the crown.", "tied at exactly 1,776 steps"]
        ])
    }

    @Test
    func aWeekAndAMonthTogetherEndOnBothCrowns() async throws {
        try await photographEveryPage(of: .weekAndMonth, expecting: [
            ["august 2026", "everyone climbed.", "august, page 1 of 5"],
            ["your month", "#2", "of 61 climbers"],
            ["week 38, page 3 of 5", "everyone climbed."],
            ["your week", "#3"],
            ["the crowns", "ezra kim took august.", "zoe ramirez took week 38.", "climb this week"]
        ])
    }

    @Test
    func weeksAwayAreOneCatchUpPage() async throws {
        try await photographEveryPage(of: .catchUp, expecting: [
            ["while you were away", "three weeks. three champions.", "your last climb was", "zoe ramirez & noah grant", "tied at exactly", "ezra kim", "climb today"]
        ])
    }

    @Test
    func aWeekWithoutClimbsIsOneShortPage() async throws {
        try await photographEveryPage(of: .noClimbs, expecting: [
            ["no climbs last week.", "last climb: 12 days ago.", "everyone climbed", "week 38 champion", "start a climb"]
        ])
    }

    @Test
    func someoneWhoNeverClimbedEndsOnTheirFirstClimb() async throws {
        try await photographEveryPage(of: .neverClimbed, expecting: [
            ["everyone climbed."],
            ["zoe ramirez took the crown.", "week 39 is open. your first climb puts you on the board.", "start your first climb"]
        ])
    }

    // MARK: - Helpers

    private func photographEveryPage(
        of variant: ChampionRecapFixtures.Variant,
        expecting pages: [[String]]
    ) async throws {
        let story = try #require(fixtures.story(variant))
        #expect(story.pages.count == pages.count, "\(variant.rawValue) has \(story.pages.count) pages")

        let registry = ChampionRegistry(repository: FakeLeaderboardResults(), isFeatureEnabled: { true }, clock: { Self.now })
        let moderationStore = ModerationStore(repository: NoBlocksModerationRepository())
        await moderationStore.hydrate(for: "viewer")
        for (index, expected) in pages.enumerated() where index < story.pages.count {
            try await RenderedScreen.host(
                PeriodRecapView(story: story, viewerId: "viewer", initialPage: index, isStatic: true) { _ in }
                    .environment(moderationStore)
                    .environment(registry)
                    .environment(AuthenticationViewModel()),
                size: RenderedScreen.iPhone16ProSize
            ) { screen in
                let copy = try await screen.copy()
                for fragment in expected {
                    #expect(copy.contains(fragment), "\(variant.rawValue) page \(index + 1) is missing \"\(fragment)\": \(copy)")
                }
                try screen.photograph(named: "recap-\(variant.id.slug)-\(index + 1)")
            }
        }
    }
}

private extension String {
    var slug: String {
        lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { result, character in
                if character == "-", result.last == "-" { return }
                result.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
