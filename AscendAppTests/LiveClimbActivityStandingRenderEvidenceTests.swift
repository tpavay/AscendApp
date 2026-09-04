import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// The Live Activity's metric row, photographed in the states whose heights
/// differ, with the title row read back level off the screen.
///
/// The standing column grew states on this branch: two lines for a plain rank,
/// three when a rank carries the climber's own history beneath it, and a title
/// over one small line where nobody else has finished. Centred, the `Rank` or
/// `Field` title floated a few points above or below `Steps` and `Time`
/// depending purely on which state the climber happened to be in - drift nobody
/// reports and everybody notices. The row is hosted through `RenderedScreen`, the
/// three titles are located on the accessibility tree and their painted ink is
/// read off a 1x capture, so a future state that changes the column's height
/// fails here rather than shipping a crooked title row.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct LiveClimbActivityStandingRenderEvidenceTests {
    private static let size = CGSize(width: 360, height: 72)
    private static let surfaces: [LiveClimbActivityMetricsRow.Surface] = [.lockScreen, .expandedIsland]

    @Test
    func aPlainRankKeepsTheTitleRowLevel() async throws {
        let state = Self.state(rank: 4, rankTotal: 27, ownClimbs: nil, board: .racing)
        #expect(state.standingSecondaryLabel == nil)

        for surface in Self.surfaces {
            try await assertTitlesLevel(state, surface: surface, standingTitle: "RANK", named: "plain-rank")
        }
    }

    @Test
    func aRankWithTheClimbersOwnHistoryBeneathItKeepsTheTitleRowLevel() async throws {
        let state = Self.state(rank: 2, rankTotal: 27, ownClimbs: (2, 5), board: .racing)
        #expect(state.standingSecondaryLabel == "2nd of your 5 climbs")

        for surface in Self.surfaces {
            try await assertTitlesLevel(state, surface: surface, standingTitle: "RANK", named: "rank-with-own-history")
        }
    }

    @Test
    func aFirstEverSoloClimberKeepsTheTitleRowLevel() async throws {
        let state = Self.state(rank: nil, rankTotal: 1, ownClimbs: nil, board: .alone)
        #expect(state.standingDetailLabel == nil)
        #expect(state.standingSecondaryLabel == "Nobody else has finished")

        for surface in Self.surfaces {
            try await assertTitlesLevel(state, surface: surface, standingTitle: "FIELD", named: "first-solo-climb")
        }
    }

    // MARK: - The row on screen

    /// Hosts the shipping row, finds each column's title on the tree, and reads
    /// the top of its painted ink off the pixels: three titles, one top edge.
    private func assertTitlesLevel(
        _ state: LiveClimbActivityAttributes.ContentState,
        surface: LiveClimbActivityMetricsRow.Surface,
        standingTitle: String,
        named name: String
    ) async throws {
        let surfaceName = surface == .lockScreen ? "lock-screen" : "expanded-island"
        try await RenderedScreen.host(
            LiveClimbActivityMetricsRow(state: state, surface: surface)
                .padding(.horizontal, 16)
                .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
                .background(Color.black)
                .foregroundStyle(.white)
                .environment(\.colorScheme, .dark),
            size: Self.size
        ) { screen in
            let texts = try await screen.texts()
            let titles = try ["STEPS", standingTitle, "TIME"].map { title in
                try #require(
                    texts.first { $0.text.caseInsensitiveCompare(title) == .orderedSame },
                    "\(title) is not on the \(surfaceName) row: \(texts.map(\.text))"
                )
            }

            let frameTops = titles.map(\.frame.minY)
            #expect(
                frameTops.allSatisfy { abs($0 - frameTops[0]) <= 0.5 },
                "the \(surfaceName) title row is not level: \(titles.map { "\($0.text)@\($0.frame.minY)" })"
            )

            let inkTops = try screen.withPixels { sampler in
                try titles.map { title in
                    let band = title.frame.insetBy(dx: -2, dy: -3)
                    let ink = try #require(
                        sampler.bounds(in: band) { $0.luminance > 60 },
                        "\(title.text) painted no ink on the \(surfaceName) row"
                    )
                    return ink.minY
                }
            }
            #expect(
                inkTops.allSatisfy { abs($0 - inkTops[0]) <= 1 },
                "the \(surfaceName) titles are painted at different heights: \(zip(titles.map(\.text), inkTops).map { "\($0)@\($1)" })"
            )

            try screen.photograph(named: "live-activity-\(surfaceName)-\(name)")
        }
    }

    // MARK: - Fixtures

    private static func state(
        rank: Int?,
        rankTotal: Int,
        ownClimbs: (placing: Int, total: Int)?,
        board: LiveClimbActivityAttributes.ContentState.Board
    ) -> LiveClimbActivityAttributes.ContentState {
        LiveClimbActivityAttributes.ContentState(
            steps: 497,
            rank: rank,
            rankTotal: rankTotal,
            ownClimbs: ownClimbs.map { .init(placing: $0.placing, total: $0.total) },
            board: board,
            durationSeconds: 350,
            progress: 0.9,
            status: .recording,
            climbPhotoURLString: nil,
            updatedAt: Date(timeIntervalSince1970: 1_787_957_195)
        )
    }
}
