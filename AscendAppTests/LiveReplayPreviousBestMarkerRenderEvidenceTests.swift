import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// The live Just Climb board the captain filmed on 2026-09-26 (`IMG_7938`): an
/// open session at 1:02:56, 5,276 steps, second of five behind a 16,645, with
/// his most-steps climb of 2,766 as the previous best.
///
/// The `BEST` marker sat at 52% of his row, which on that row is the middle of
/// his name, and drew its line and its vertical word straight through it
/// ("Tyler Pava|BEST|y"). Decided on 2026-09-26 (`best-label-orientation`): the
/// line passes behind the row's content and the word flies horizontally from
/// the top of the line, so nothing of the marker draws over the name - at any
/// name length and any text size.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct LiveReplayPreviousBestMarkerRenderEvidenceTests {
    private static let panelSize = CGSize(width: 402, height: 560)

    /// Every case where the previous best lands on the climber's name or `YOU`
    /// chip: the captain's own board, a name long enough to truncate, and the
    /// text sizes either side of the default.
    nonisolated static let boardsWithTheMarkerOnTheName: [BoardCase] = [
        BoardCase(name: "captain", displayName: "Tyler Pavay", dynamicTypeSize: .large),
        BoardCase(name: "long-name", displayName: "Maximiliano Castellanos-Oppenheimer", dynamicTypeSize: .large),
        BoardCase(name: "type-xsmall", displayName: "Tyler Pavay", dynamicTypeSize: .xSmall),
        BoardCase(name: "type-xxxlarge", displayName: "Tyler Pavay", dynamicTypeSize: .xxxLarge),
        BoardCase(name: "type-accessibility3", displayName: "Tyler Pavay", dynamicTypeSize: .accessibility3)
    ]

    /// The marker adds nothing to the band the name and chip occupy - that band
    /// reads pixel for pixel the same as the same board with no previous best,
    /// where the 2026-09-26 marker drew both its line and its word - and it is
    /// still labelled: the flag flies from the top of the line, in the row's
    /// top margin.
    @Test(arguments: boardsWithTheMarkerOnTheName)
    func theMarkerIsLabelledAndDrawsNothingOverTheName(_ board: BoardCase) async throws {
        let withMarker = try await Self.read(board, showsPreviousBest: true)
        let withoutMarker = try await Self.read(board, showsPreviousBest: false)

        #expect(withMarker.rowFrame.integral == withoutMarker.rowFrame.integral)
        #expect(
            withMarker.nameBand == withoutMarker.nameBand,
            "the BEST marker changed pixels across the name band of \(board.name)"
        )
        #expect(withMarker.flagInk > 20, "no BEST flag was drawn on \(board.name)")
        #expect(withoutMarker.flagInk == 0)
    }

    /// The reviewer-facing photographs, including the positions where the
    /// marker is clear of the name: under the avatar, in the gap before the
    /// step count, and beside the step count.
    @Test
    func photographsOfTheBoard() async throws {
        guard RenderedScreen.isPhotographing else { return }

        let boards: [(String, CaptainsOpenClimbBoard)] = [
            ("captain", CaptainsOpenClimbBoard()),
            ("best-under-avatar", CaptainsOpenClimbBoard(previousBestSteps: 700)),
            ("best-in-clear-space", CaptainsOpenClimbBoard(previousBestSteps: 3_750)),
            ("best-near-number", CaptainsOpenClimbBoard(previousBestSteps: 4_500))
        ] + Self.boardsWithTheMarkerOnTheName.dropFirst().map {
            ($0.name, CaptainsOpenClimbBoard(displayName: $0.displayName, dynamicTypeSize: $0.dynamicTypeSize))
        }

        for (name, board) in boards {
            try await RenderedScreen.host(board, size: Self.panelSize) { screen in
                _ = try await screen.copy()
                try screen.photograph(named: "open-just-climb-\(name)")
            }
        }
    }

    // MARK: - Helpers

    struct BoardCase: Sendable, CustomTestStringConvertible {
        let name: String
        let displayName: String
        let dynamicTypeSize: DynamicTypeSize

        var testDescription: String { name }
    }

    private struct Reading {
        let rowFrame: CGRect
        let nameBand: [RGBA]
        let flagInk: Int
    }

    private static func read(_ board: BoardCase, showsPreviousBest: Bool) async throws -> Reading {
        let view = CaptainsOpenClimbBoard(
            displayName: board.displayName,
            dynamicTypeSize: board.dynamicTypeSize,
            showsPreviousBest: showsPreviousBest
        )

        return try await RenderedScreen.host(view, size: panelSize) { screen in
            let rowFrame = try #require(
                try await screen.frame(ofElementLabelled: board.displayName),
                "the live row was not on screen"
            )
            let markerX = rowFrame.minX + rowFrame.width * CaptainsOpenClimbBoard.previousBestFraction
            // The name and chip are centred in the row; this is the band their
            // glyphs' cap height fills. The line's pieces stop the clearance
            // short of the name's frame, and a name scaled down to fit has a
            // shorter frame, so their soft shadow is allowed to reach the rows
            // of pixels just above and below the glyphs.
            let nameBand = CGRect(x: rowFrame.minX, y: rowFrame.midY - 6, width: rowFrame.width, height: 12)
            let flag = CGRect(x: markerX + 3, y: rowFrame.minY + 2, width: 22, height: 11)

            return try screen.withPixels(scale: 2) { pixels in
                Reading(
                    rowFrame: rowFrame,
                    nameBand: pixels.pixels(in: nameBand),
                    flagInk: pixels.count(in: flag) { $0.luminance > 200 }
                )
            }
        }
    }
}

/// The live race panel exactly as `LiveClimbSessionView` configures it on an
/// open Just Climb, fed the rows the shipping window hands it.
struct CaptainsOpenClimbBoard: View {
    var displayName = "Tyler Pavay"
    var previousBestSteps = 2_766
    var dynamicTypeSize: DynamicTypeSize = .large
    var showsPreviousBest = true

    static let liveSteps = 5_276
    /// Where the captain's 2,766 sits on his 5,276-step row.
    static let previousBestFraction = 2_766.0 / 5_276.0
    private static let elapsedSeconds = 3_776

    var body: some View {
        let board = Self.board(displayName: displayName, previousBestSteps: previousBestSteps)

        NavigationStack {
            LiveReplayLeaderboardPanel(
                rows: board.rows,
                progressScaleSteps: max(JustClimbGoal.defaultOpenStepScale, Self.liveSteps),
                targetStepGoal: nil,
                progress: 1,
                currentUserPhotoURL: nil,
                previousBestStepsAtBucket: showsPreviousBest ? board.previousBestSteps : nil,
                fetchFailed: false,
                standing: .racing(
                    field: nil,
                    ownClimbs: LiveReplayPersonalPlacing(placing: 1, total: 11)
                ),
                tint: .accent,
                effectiveColorScheme: .dark,
                showsFilter: false
            )
            .padding(16)
            .background(Color.black)
        }
        .environment(\.dynamicTypeSize, dynamicTypeSize)
    }

    private static func board(
        displayName: String,
        previousBestSteps: Int
    ) -> (rows: [ModeratedReplayLeaderboardRow], previousBestSteps: Int?) {
        let previousBest = LiveReplayLeaderboardRow(
            id: "own-best",
            rank: nil,
            displayName: displayName,
            avatarToken: "TP",
            photoURL: nil,
            stepsAtBucket: previousBestSteps,
            finalSteps: previousBestSteps,
            deltaFromUser: previousBestSteps - liveSteps,
            isCurrentUser: true,
            isLiveAttempt: false,
            isPersonalBest: true,
            completionDurationSeconds: 1_980,
            userId: "captain"
        )
        let rivals = [
            rival("viktor", rank: 1, name: "Viktor Blomgren", steps: 16_645, gender: "man", age: 27, city: "Stockholm"),
            rival("urjita", rank: 3, name: "Urjita Das", steps: 836, gender: "woman", age: 27, city: "Chicago"),
            rival("tony", rank: 4, name: "Tony Koshar", steps: 500, gender: "man", age: 29, city: "Baltimore"),
            rival("john", rank: 5, name: "John Smith", steps: 149, gender: "man", age: 32, city: "Chicago")
        ]
        let window = LiveReplayLeaderboardWindow(
            context: .justClimbGlobal(),
            bucketIndex: 359,
            currentSteps: liveSteps,
            fetchedAt: Date(timeIntervalSince1970: 1_790_440_511),
            rows: rivals + [previousBest],
            currentUserRank: 2,
            totalClimbers: 5,
            ownPreviousCompletionRow: previousBest,
            ownClimbs: LiveReplayPersonalPlacing(placing: 1, total: 11)
        )
        let rows = window.locallyRankedRows(
            currentSteps: liveSteps,
            currentElapsedSeconds: elapsedSeconds,
            displayName: displayName
        )

        return (
            rows.map {
                CrossUserIdentityAdapter.replayRow($0, blockedUserIds: [], isBlockListHydrated: true)
            },
            window.previousBestStepsAtBucket(currentElapsedSeconds: elapsedSeconds)
        )
    }

    private static func rival(
        _ id: String,
        rank: Int,
        name: String,
        steps: Int,
        gender: String,
        age: Int,
        city: String
    ) -> LiveReplayLeaderboardRow {
        LiveReplayLeaderboardRow(
            id: id,
            rank: rank,
            displayName: name,
            avatarToken: PublicClimberIdentity.avatarToken(for: name),
            photoURL: nil,
            stepsAtBucket: steps,
            finalSteps: steps,
            deltaFromUser: 0,
            isCurrentUser: false,
            isPersonalBest: false,
            completionDurationSeconds: 1_200,
            userId: id,
            gender: gender,
            age: age,
            locationCity: city
        )
    }
}
