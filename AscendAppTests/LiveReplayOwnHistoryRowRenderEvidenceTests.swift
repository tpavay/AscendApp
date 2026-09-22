import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Photographs the live board a repeat climber sees, off the rows the shipping
/// window actually hands the panel.
///
/// Two captain screenshots shaped this board. His second St Peter's Basilica
/// attempt (2026-09-01) drew his own earlier climb as a stranger: initials on a
/// plain circle, a `M · 27 · Chicago` subtitle, no `YOU`, a tap target into
/// another climber's profile. Then production 1.0.1 (2026-09-22) drew that
/// earlier climb as a second row of his, wearing `YOU`, beneath the run on the
/// machine. The rule now is the one The rank model states: the previous best is
/// the `BEST` marker inside his live row and never a row of its own.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct LiveReplayOwnHistoryRowRenderEvidenceTests {
    private static let panelSize = CGSize(width: 393, height: 420)
    private static let targetSteps = 551

    @Test
    func theClimbersOwnEarlierAttemptIsTheMarkerAndNotASecondRow() async throws {
        try await RenderedScreen.host(RepeatClimberBoardProof(), size: Self.panelSize) { screen in
            let texts = try await screen.texts()
            let copy = texts.map { $0.text.lowercased() }.joined(separator: " ")

            // One row of his, saying so once. The badge is counted apart from the
            // footer's "OF YOUR N CLIMBS", which contains the same three letters
            // and is a statement about the field rather than about a row.
            #expect(copy.components(separatedBy: "tyler pavay").count - 1 == 1)
            #expect(Self.youBadgeCount(in: copy) == 1)

            // A stranger's demographic subtitle is what once made his own record
            // read as somebody else's row.
            #expect(!copy.contains("chicago"))

            // The record he is chasing is not a row. The header carries the
            // climb's own target once, as "551 STEPS", and that is the only
            // 551 on the panel: no row holds the count his finished attempt
            // would have shown, and the run on the machine is the row there is.
            #expect(copy.components(separatedBy: "551").count - 1 == 1)
            #expect(copy.contains("497"))

            try screen.photograph(named: "repeat-climber-live-board")
        }
    }

    /// The captain's bucket 35. He is the only climber who has ever finished
    /// this tower, so the board states no leaderboard placing at all - not a
    /// `#1`, not a `1 CLIMBER` line beside one - and states where this run sits
    /// among his own climbs instead.
    @Test
    func aClimberAloneOnTheTowerIsPlacedAmongTheirOwnClimbs() async throws {
        try await RenderedScreen.host(RepeatClimberBoardProof(), size: Self.panelSize) { screen in
            let copy = try await screen.copy()

            #expect(copy.contains("of your 2 climbs"))
            #expect(copy.contains(2.rankOrdinalText.lowercased()))

            // The two things that must not be on this board: a field line naming
            // a population of one, and any leaderboard ordinal.
            #expect(!copy.contains("1 climber"))
            #expect(!copy.contains("#"))

            try screen.photograph(named: "repeat-climber-alone-live-board")
        }
    }

    /// The same board once real rivals exist. Both numbers show and each names
    /// its own population, so neither can be read as the other.
    @Test
    func aBoardWithRivalsNamesTheLeaderboardFieldAndHisOwnClimbsSeparately() async throws {
        let proof = RepeatClimberBoardProof(
            standing: .racing(
                field: LiveReplayFieldSize(population: .climbers, count: 27),
                ownClimbs: LiveReplayPersonalPlacing(placing: 2, total: 5)
            )
        )

        try await RenderedScreen.host(proof, size: Self.panelSize) { screen in
            let copy = try await screen.copy()

            #expect(copy.contains("27 climbers"))
            #expect(copy.contains("of your 5 climbs"))

            try screen.photograph(named: "repeat-climber-rivals-live-board")
        }
    }

    // MARK: - Helpers

    /// Occurrences of the `YOU` badge, excluding the `YOUR` the field line uses.
    private static func youBadgeCount(in text: String) -> Int {
        let all = text.components(separatedBy: "you").count - 1
        let possessive = text.components(separatedBy: "your").count - 1
        return all - possessive
    }

    /// The window the repository returns at bucket 35 - his finished record,
    /// held at the target, and the run still on the machine - and the rows the
    /// board draws from it, which is the run alone.
    fileprivate static func board() -> (rows: [ModeratedReplayLeaderboardRow], previousBestSteps: Int?) {
        let history = LiveReplayLeaderboardRow(
            id: "first-attempt",
            rank: nil,
            displayName: "Tyler Pavay",
            avatarToken: "TP",
            photoURL: nil,
            stepsAtBucket: targetSteps,
            finalSteps: targetSteps,
            deltaFromUser: 54,
            isCurrentUser: true,
            isLiveAttempt: false,
            isPersonalBest: true,
            completionDurationSeconds: 346.66342401504517,
            userId: "kC8GSV7hCDZY9waZhIS9CimQ70y2",
            gender: "man",
            age: 27,
            locationCity: "Chicago"
        )
        let window = LiveReplayLeaderboardWindow(
            context: .liveClimb(climbId: "st-peters-basilica", targetSteps: targetSteps),
            bucketIndex: 35,
            currentSteps: 497,
            fetchedAt: Date(timeIntervalSince1970: 1_787_957_195),
            rows: [history.holdingFinalSteps(currentSteps: 497)],
            currentUserRank: 1,
            totalClimbers: 1,
            ownPreviousCompletionRow: history.holdingFinalSteps(currentSteps: 497)
        )
        let rows = window.locallyRankedRows(
            currentSteps: 497,
            currentElapsedSeconds: 350,
            displayName: "Tyler Pavay"
        )

        return (
            rows.map {
                CrossUserIdentityAdapter.replayRow(
                    $0,
                    blockedUserIds: [],
                    isBlockListHydrated: true
                )
            },
            window.previousBestStepsAtBucket(currentElapsedSeconds: 350)
        )
    }
}

/// The live race panel exactly as `LiveClimbSessionView` configures it.
private struct RepeatClimberBoardProof: View {
    var standing: LiveReplayLiveStanding = .alone(
        ownClimbs: LiveReplayPersonalPlacing(placing: 2, total: 2)
    )

    var body: some View {
        let board = LiveReplayOwnHistoryRowRenderEvidenceTests.board()

        NavigationStack {
            LiveReplayLeaderboardPanel(
                rows: board.rows,
                progressScaleSteps: 551,
                targetStepGoal: 551,
                progress: 0.9,
                currentUserPhotoURL: nil,
                previousBestStepsAtBucket: board.previousBestSteps,
                fetchFailed: false,
                standing: standing,
                tint: .accent,
                effectiveColorScheme: .dark
            )
            .padding(16)
            .background(Color.black)
        }
    }
}
