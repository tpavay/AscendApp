import SwiftUI
import Testing
@testable import AscendApp

/// Evidence for Home's Weekly Rank and Streak tiles.
///
/// On 2026-09-27, a Sunday, the captain's sheet read "2 wks · in a row · ends Sunday" after a
/// week of climbs, beside a rank tile whose bare "-" read as a minus sign on the streak. The
/// streak now counts the app's Monday week and stops warning once this week holds a climb, and
/// no tile draws a lone dash. Copy is asserted from the accessibility tree; the tiles are
/// photographed only when `ASCEND_EVIDENCE_DIR` is set.
@MainActor
@Suite(.hostsAWindow)
struct HomeRankStreakEvidenceTests {
    @Test
    func aSecuredWeekCountsWithoutADeadline() async throws {
        let copy = try await hostAndPhotograph(
            streak: WeeklyStreak(weeks: 1, isCurrentWeekSecured: true),
            named: "home-streak-secured"
        )

        #expect(copy.contains("streak: 1 week in a row. this week counts."))
        #expect(!copy.contains("sunday"))
    }

    @Test
    func anUnclimbedWeekNamesTheDeadline() async throws {
        let copy = try await hostAndPhotograph(
            streak: WeeklyStreak(weeks: 2, isCurrentWeekSecured: false),
            named: "home-streak-unsecured"
        )

        #expect(copy.contains("streak: 2 weeks in a row. climb by sunday to keep it."))
    }

    @Test
    func noStreakDaresTheFirstClimb() async throws {
        let copy = try await hostAndPhotograph(streak: .none, named: "home-streak-none")

        #expect(copy.contains("no streak yet. climb this week to start one."))
    }

    @Test
    func anUnrankedTileSaysSoInWords() async throws {
        let text = try await RenderedScreen.recognizedText(
            of: section(streak: WeeklyStreak(weeks: 3, isCurrentWeekSecured: true)),
            scale: 3
        )

        #expect(text.contains("unranked"), "Read: \(text)")
    }

    @Test
    func aLoadingRankDrawsAPlaceholderRatherThanADash() async throws {
        let copy = try await hostAndPhotograph(
            streak: WeeklyStreak(weeks: 2, isCurrentWeekSecured: true),
            isRankLoading: true,
            named: "home-rank-loading"
        )

        #expect(copy.contains("weekly rank by steps is updating."))
    }

    private func section(streak: WeeklyStreak, isRankLoading: Bool = false) -> some View {
        HomeRankStreakSection(
            weeklyRankSummary: nil,
            isRankLoading: isRankLoading,
            streak: streak,
            onRankTapped: {},
            onStreakTapped: {}
        )
        .padding(16)
        .frame(width: 402)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }

    private func hostAndPhotograph(
        streak: WeeklyStreak,
        isRankLoading: Bool = false,
        named name: String
    ) async throws -> String {
        try RenderedScreen.photograph(section(streak: streak, isRankLoading: isRankLoading), named: name)
        return try await RenderedScreen.host(section(streak: streak, isRankLoading: isRankLoading)) { screen in
            try await screen.copy { $0.contains("streak") }
        }
    }
}
