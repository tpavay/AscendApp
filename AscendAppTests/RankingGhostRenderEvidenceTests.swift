import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Visual evidence for the ranking-and-ghost design the captain locked on
/// 2026-09-01.
///
/// Every case hosts a shipping view in a real `UIWindow` -
/// `LiveClimbSummaryRankHeroView` and `LiveReplayLeaderboardPanel` - through
/// `RenderedScreen`, reads the copy back off the accessibility tree and the
/// marker's position off a 1x capture. Nothing is redrawn for the test.
///
/// PNGs land in `ASCEND_EVIDENCE_DIR` when set and are not taken otherwise.
@MainActor
@Suite(.hostsAWindow)
struct RankingGhostRenderEvidenceTests {
    typealias Hero = LiveClimbSummaryRankHero

    // MARK: - The finish card

    /// The case that parked the other task, rendered: five climbs on St. Peter's,
    /// today's run second-fastest, nobody else on the tower. The screen used to
    /// read `1st` over `FASTEST OF 1 CLIMBER`.
    @Test
    func aSoloSlowerRepeatShowsItsPlacingAmongTheClimbersOwnClimbs() async throws {
        try await RenderedScreen.host(
            heroPanel(
                standing: Hero.Standing(rank: 1, total: 1, basis: .atCompletion),
                personalPlacing: PersonalClimbPlacing(ordinal: 2, total: 5),
                moment: .freshCompletion
            ),
            size: Self.screenSize
        ) { screen in
            let text = try await screen.copy()

            #expect(text.contains("of your 5 climbs"))
            #expect(!text.contains("climber"))
            #expect(!text.contains("fastest"))
            #expect(!text.contains("rank you just earned"))

            try screen.photograph(named: "finish-card-solo-slower-repeat")
        }
    }

    /// The same component when the repeat was faster. One ordinal covers improved
    /// and not-improved, so there is no separate personal-best card.
    @Test
    func aSoloPersonalBestUsesTheSameCard() async throws {
        try await RenderedScreen.host(
            heroPanel(
                standing: Hero.Standing(rank: 1, total: 1, basis: .atCompletion),
                personalPlacing: PersonalClimbPlacing(ordinal: 1, total: 5),
                moment: .freshCompletion
            ),
            size: Self.screenSize
        ) { screen in
            let text = try await screen.copy()

            #expect(text.contains("of your 5 climbs"))
            #expect(!text.contains("climber"))

            try screen.photograph(named: "finish-card-solo-personal-best")
        }
    }

    /// The First Ascent card: the gold flag and the claim, and nothing else.
    @Test
    func aFirstAscentCardIsTheFlagAndTheClaim() async throws {
        try await RenderedScreen.host(
            heroPanel(
                standing: Hero.Standing(rank: 1, total: 1, basis: .atCompletion),
                personalPlacing: PersonalClimbPlacing(ordinal: 1, total: 1),
                claimsFirstAscent: true,
                moment: .freshCompletion
            ),
            size: Self.screenSize
        ) { screen in
            let text = try await screen.copy()

            #expect(text.contains("first ascent claimed"))
            #expect(!text.contains("climber"))
            #expect(!text.contains("of your"))

            try screen.photograph(named: "finish-card-first-ascent")
        }
    }

    /// The same card reopened from Workout Detail after the climber has gone back
    /// to the tower three more times. The claim is permanent, so the screen is
    /// identical - it used to become `4TH OF YOUR 4 CLIMBS`.
    @Test
    func aFirstAscentCardStillRendersAfterTheClimberReturnsToTheTower() async throws {
        try await RenderedScreen.host(
            heroPanel(
                standing: Hero.Standing(rank: 1, total: 1, basis: .atCompletion),
                personalPlacing: PersonalClimbPlacing(ordinal: 4, total: 4),
                claimsFirstAscent: true,
                moment: .retrospective
            ),
            size: Self.screenSize
        ) { screen in
            let text = try await screen.copy()

            #expect(text.contains("first ascent claimed"))
            #expect(!text.contains("of your 4 climbs"))

            try screen.photograph(named: "finish-card-first-ascent-reopened")
        }
    }

    /// A real field of climbers keeps the leaderboard rank in the hero, with the
    /// field named beneath it exactly as it ships today.
    @Test
    func aRealFieldKeepsTheLeaderboardRankInTheHero() async throws {
        try await RenderedScreen.host(
            heroPanel(
                standing: Hero.Standing(rank: 2, total: 2, basis: .atCompletion),
                personalPlacing: PersonalClimbPlacing(ordinal: 2, total: 5),
                moment: .freshCompletion
            ),
            size: Self.screenSize
        ) { screen in
            let text = try await screen.copy()

            #expect(text.contains("fastest of 2 climbers"))
            #expect(!text.contains("of your 5 climbs"))

            try screen.photograph(named: "finish-card-rival-repeat")
        }
    }

    // MARK: - The live board

    /// The marker while the climber is behind their own best: one line inside
    /// their own row, no rank cell of its own, and no number anywhere near it.
    ///
    /// The line is measured off the pixels rather than read: it lands on the same
    /// progress scale the row's own fill is drawn against, which is what makes
    /// the visible gap between them mean anything.
    @Test
    func theLiveBoardMarksThePreviousBestInsideTheClimbersOwnRow() async throws {
        try await RenderedScreen.host(
            leaderboardPanel(currentSteps: 347, markerSteps: 414),
            size: Self.screenSize
        ) { screen in
            let text = try await screen.copy()

            let markerX = try #require(
                try screen.withPixels(markerColumnX),
                "no marker line was drawn"
            )
            #expect(abs(markerX - expectedMarkerX(steps: 414)) <= 6)

            #expect(text.contains("347"))
            // Nothing states the gap. The visible distance is the whole message.
            #expect(!text.contains("catch"))
            #expect(!text.contains("steps ahead"))
            #expect(!text.contains("behind"))
            // The best is not a row: it takes no rank cell and shows no step count.
            #expect(!text.contains("414"))

            try screen.photograph(named: "live-board-previous-best-behind")
        }
    }

    /// The same board once the climber has passed their own best. The line is in
    /// the identical place and looks identical - which side the fill sits on is
    /// the entire signal - and the standings did not move, because the best never
    /// held one.
    @Test
    func passingThePreviousBestChangesTheGapAndNothingElse() async throws {
        let behindMarkerX = try #require(
            try await RenderedScreen.host(
                leaderboardPanel(currentSteps: 347, markerSteps: 414),
                size: Self.screenSize
            ) { screen in
                try screen.withPixels(markerColumnX)
            }
        )

        try await RenderedScreen.host(
            leaderboardPanel(currentSteps: 470, markerSteps: 414),
            size: Self.screenSize
        ) { screen in
            let text = try await screen.copy()

            let passedMarkerX = try #require(
                try screen.withPixels(markerColumnX),
                "no marker line was drawn"
            )
            #expect(abs(passedMarkerX - behindMarkerX) <= 2)
            #expect(abs(passedMarkerX - expectedMarkerX(steps: 414)) <= 6)

            #expect(text.contains("470"))
            #expect(!text.contains("catch"))
            #expect(!text.contains("414"))

            try screen.photograph(named: "live-board-previous-best-passed")
        }
    }

    /// Early in the race both the climber and their best are near the start, so
    /// the marker sits over the row's leading chrome. Evidence that the state is
    /// legible rather than assumed: the line is still found where the best
    /// reached, over that chrome.
    @Test
    func theMarkerStaysLegibleEarlyInTheRace() async throws {
        try await RenderedScreen.host(
            leaderboardPanel(currentSteps: 22, markerSteps: 48),
            size: Self.screenSize
        ) { screen in
            let markerX = try #require(
                try screen.withPixels { markerColumnX(in: $0, from: 0) },
                "no marker line was drawn over the leading chrome"
            )
            #expect(abs(markerX - expectedMarkerX(steps: 48)) <= 6)

            try screen.photograph(named: "live-board-previous-best-early")
        }
    }

    // MARK: - The Just Me rail

    /// The same marker turned on its side (JM-G): one horizontal line at the
    /// height the previous best reached, `BEST` above it, narrowed to the track.
    /// No step count, no delta, no comparison sentence.
    @Test
    func theJustMeRailCarriesTheSameMarkerTurnedOnItsSide() async throws {
        try await RenderedScreen.host(
            LiveClimbProgressRail(
                    progress: 347.0 / 551,
                    previousBestProgress: 414.0 / 551,
                    summitSteps: 551
                )
                .frame(width: 64)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 24)
                .background(Color.black),
            size: Self.screenSize
        ) { screen in
            let text = try await screen.copy()

            #expect(text.contains("summit"))
            #expect(text.contains("551"))
            #expect(text.contains("start"))
            // The marker states no number of its own.
            #expect(!text.contains("414"))
            #expect(!text.contains("347"))
            #expect(!text.contains("catch"))

            try screen.photograph(named: "just-me-rail-previous-best")
        }
    }

    // MARK: - Measuring the marker

    /// Where the marker's line should land: the panel's own horizontal padding
    /// plus the row's share of the same step scale its progress fill uses.
    private func expectedMarkerX(steps: Int) -> CGFloat {
        let rowWidth = Self.screenSize.width - (Self.panelPadding * 2)
        return Self.panelPadding + rowWidth * (CGFloat(steps) / 551)
    }

    /// The x of the tallest near-white vertical run inside the row band.
    ///
    /// The scan is confined to the row and to its trailing half, where the only
    /// white the panel draws is the marker itself: the rank cell and the step
    /// count are lime, the `YOU` pill is black on lime, and the climber's name
    /// sits well to the left of the band.
    private func markerColumnX(in pixels: PixelSampler) -> CGFloat? {
        markerColumnX(in: pixels, from: Self.screenSize.width * 0.45)
    }

    /// The x of the tallest near-white vertical run inside the row band, scanned
    /// from `firstColumn` (points) to the trailing edge. Read off a 1x capture:
    /// a stroked 2pt line is two pixels wide there, and a column position does
    /// not need more.
    private func markerColumnX(in pixels: PixelSampler, from firstColumn: CGFloat) -> CGFloat? {
        let scale = pixels.scale
        var tallest = (column: -1, height: 0)

        for column in Int(firstColumn * scale)..<pixels.width {
            var height = 0
            for row in Int(CGFloat(Self.rowBandTop) * scale)..<Int(CGFloat(Self.rowBandBottom) * scale)
            where pixels.pixel(x: column, y: row).isNearWhite {
                height += 1
            }
            if height > tallest.height {
                tallest = (column, height)
            }
        }

        // A stroked 2pt line fills most of the band; a stacked letter does not.
        let bandHeight = Int(CGFloat(Self.rowBandBottom - Self.rowBandTop) * scale)
        guard tallest.column >= 0, tallest.height > bandHeight / 2 else { return nil }

        return CGFloat(tallest.column) / scale
    }

    /// A band comfortably inside the single row this panel draws, below the
    /// header rule and above the field-size line.
    private static let rowBandTop = 135
    private static let rowBandBottom = 185
    private static let panelPadding: CGFloat = 16

    // MARK: - Rendering

    private func heroPanel(
        standing: Hero.Standing?,
        personalPlacing: PersonalClimbPlacing?,
        claimsFirstAscent: Bool = false,
        moment: Hero.Moment
    ) throws -> some View {
        let hero = try #require(Hero.make(
            isClimbContext: true,
            moment: moment,
            standings: [standing],
            personalPlacing: personalPlacing,
            claimsFirstAscent: claimsFirstAscent,
            sync: Hero.SyncState(
                phase: .published,
                hasRankContext: true,
                rankResolution: .settled
            ),
            copy: Hero.Copy()
        ))

        return LiveClimbSummaryRankHeroView(
            hero: hero,
            rankingMetric: .fastestCompletion,
            fieldPopulation: .climbers,
            onRetrySync: {}
        )
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
    }

    private func leaderboardPanel(currentSteps: Int, markerSteps: Int) -> some View {
        let rows = [
            CrossUserIdentityAdapter.replayRow(
                LiveReplayLeaderboardRow.currentUser(
                    rank: 1,
                    steps: currentSteps,
                    displayName: "Tyler P."
                ),
                blockedUserIds: [],
                isBlockListHydrated: true
            )
        ]

        return LiveReplayLeaderboardPanel(
            rows: rows,
            progressScaleSteps: 551,
            targetStepGoal: 551,
            progress: min(Double(currentSteps) / 551, 1),
            currentUserPhotoURL: nil,
            previousBestStepsAtBucket: markerSteps,
            fetchFailed: false,
            field: LiveReplayFieldSize(population: .climbers, count: 1),
            tint: .accent,
            effectiveColorScheme: .dark,
            showsFilter: false
        )
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
    }

    private static let screenSize = CGSize(width: 393, height: 400)
}
