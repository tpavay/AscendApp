import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Evidence that every board names the window it covers.
///
/// The captain photographed three Steps tabs on 2026-08-01: a populated WEEKLY board
/// and a MONTHLY board reading "No entries yet." Unlabelled, that pair reads as data
/// loss. It is not: the week of Mon Jul 27 runs into Aug 2, so on the 1st it carries
/// July steps the freshly opened August board cannot. The photographs are of the
/// shipping `LeaderboardView` - header, tab filters, window label and empty state -
/// so the label and the copy are photographed exactly where a climber meets them.
///
/// Signed out, `setupAndLoad` returns before it loads anything, which is what puts the
/// board in the empty state the monthly tab was actually in.
///
/// The labels are asserted from `LeaderboardPeriod`, and the shipping board is hosted
/// through `RenderedScreen` to prove the label is on its accessibility tree; it is
/// photographed only when `ASCEND_EVIDENCE_DIR` is set. Nothing reads the photographs
/// back - these are evidence, not golden-image assertions.
@MainActor
@Suite(.hostsAWindow)
struct LeaderboardWindowLabelEvidenceTests {
    @Test
    func weeklyBoardNamesTheWeekItCovers() async throws {
        let period = LeaderboardTimeFrame.weekly.currentPeriod()
        // A dated range, never a bare "This week" - the dates are the whole point.
        #expect(period.windowLabel.contains("-"))

        try await hostAndPhotograph(
            leaderboard(initialTimeFrame: .weekly),
            showing: period.windowLabel,
            named: "leaderboard-window-label-weekly",
            height: 620
        )
    }

    /// The board the captain read as broken. Early in August it is young, not empty of
    /// data that should be there, and the label plus the empty-state subject say so.
    @Test
    func monthlyBoardNamesTheMonthAndStatesItIsEmpty() async throws {
        let period = LeaderboardTimeFrame.monthly.currentPeriod()
        #expect(period.windowSubject == period.windowLabel)

        try await hostAndPhotograph(
            leaderboard(initialTimeFrame: .monthly),
            showing: period.windowLabel,
            named: "leaderboard-window-label-monthly-empty",
            height: 620
        )
    }

    @Test
    func yearlyBoardNamesTheYearItCovers() async throws {
        let period = LeaderboardTimeFrame.yearly.currentPeriod()
        // The window is keyed on the board's canonical calendar, not the viewer's: read the year
        // the same way, or a New Year's Eve viewer west of UTC reads a 2026 window as 2025.
        var boardCalendar = Calendar(identifier: .gregorian)
        boardCalendar.timeZone = LeaderboardTimeFrame.canonicalTimeZone
        let year = boardCalendar.component(.year, from: period.startAt)
        #expect(period.windowLabel.contains(String(year)))

        try await hostAndPhotograph(
            leaderboard(initialTimeFrame: .yearly),
            showing: period.windowLabel,
            named: "leaderboard-window-label-yearly",
            height: 620
        )
    }

    // MARK: - Fixtures

    private func leaderboard(initialTimeFrame: LeaderboardTimeFrame) throws -> some View {
        let container = try RetainedModelContainer.inMemory(for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self, LeaderboardStats.self)

        return NavigationStack {
            LeaderboardView(initialTimeFrame: initialTimeFrame, viewSource: .tab)
        }
        .environment(AuthenticationViewModel())
        .environment(ModerationStore.shared)
        .environment(NetworkConnectivityService.shared)
        .environment(TabRouter())
        .modelContainer(container)
    }

    // MARK: - The board on screen

    /// Hosts the shipping board in a real window so the scroll content lays out, proves the
    /// window label reached the screen, and photographs it when this run keeps photographs.
    private func hostAndPhotograph<Content: View>(
        _ view: @autoclosure () throws -> Content,
        showing windowLabel: String,
        named name: String,
        height: CGFloat
    ) async throws {
        let size = CGSize(width: 390, height: height)
        try await RenderedScreen.host(
            try view()
                .frame(width: size.width, height: size.height, alignment: .top)
                .background(Color.black)
                .environment(\.colorScheme, .dark),
            size: size
        ) { screen in
            let copy = try await screen.copy()
            #expect(
                copy.contains("showing \(windowLabel.lowercased())"),
                "The board does not name its window (\(windowLabel)) on screen: \(copy)"
            )
            try screen.photograph(named: name)
        }
    }
}
