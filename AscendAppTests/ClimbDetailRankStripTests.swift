import CoreGraphics
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

@MainActor
struct ClimbDetailRankStripTests {
    @Test("A finisher sees their order among all finishers")
    func personalFinisherOrderRendersInTheStrip() {
        let viewModel = makeViewModel(completedCount: 12, personalOrder: 4)

        #expect(viewModel.stripOrderText == "#4/12")
    }

    @Test("A climber without a finisher order sees no rank strip")
    func missingPersonalFinisherOrderRendersNothing() {
        let viewModel = makeViewModel(completedCount: 12, personalOrder: nil)

        #expect(viewModel.stripOrderText == nil)
    }

    @Test("Artwork fills the hero card when the rank strip is absent")
    func absentRankStripLeavesNoLeadingGap() throws {
        let row = try renderHeroMidRow(stripOrderText: nil)

        #expect(
            row.artworkRatio(fromPoint: 8, toPoint: Self.heroWidth - 8) > 0.98,
            "The artwork should reach both hero-card edges without a reserved 48pt strip"
        )
    }

    @Test("The rank strip covers the leading 48pt of the hero card")
    func presentRankStripOccupiesTheLeadingStripWidth() throws {
        let row = try renderHeroMidRow(stripOrderText: "#4/12")

        #expect(
            row.artworkRatio(fromPoint: 2, toPoint: 46) == 0,
            "The strip should cover the artwork across the leading 48pt"
        )
        #expect(
            row.artworkRatio(fromPoint: 52, toPoint: Self.heroWidth - 8) > 0.98,
            "The strip should be exactly 48pt wide, leaving the rest of the hero as artwork"
        )
    }

    private static let heroWidth: CGFloat = 353
    private static let heroHeight: CGFloat = 390

    private static let artworkMarker = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)

    /// One pixel per point across the hero card's vertical middle, read off a 1x capture: whether
    /// a point is artwork or strip is a colour question, and a colour reads the same at any scale.
    private struct HeroMidRow {
        let pixels: [RGBA]

        func artworkRatio(fromPoint: CGFloat, toPoint: CGFloat) -> Double {
            let sampled = Int(fromPoint)..<Int(toPoint)
            let artworkPixelCount = sampled.count(where: { x in
                let pixel = pixels[x]
                return pixel.red > 150
                    && pixel.green < 30
                    && pixel.blue < 30
                    && pixel.alpha > 240
            })

            return Double(artworkPixelCount) / Double(sampled.count)
        }
    }

    private func renderHeroMidRow(stripOrderText: String?) throws -> HeroMidRow {
        let hero = ClimbDetailHeroCardFront(
            climb: .preview,
            subtitle: Climb.preview.displayLocation,
            stripOrderText: stripOrderText
        ) {
            Self.artworkMarker
        }
        .frame(width: Self.heroWidth, height: Self.heroHeight)
        .clipShape(RoundedRectangle(cornerRadius: 28))

        return try RenderedScreen.withOffscreenPixels(of: hero) { pixels in
            HeroMidRow(
                pixels: pixels.pixels(
                    in: CGRect(x: 0, y: Self.heroHeight / 2, width: Self.heroWidth, height: 1)
                )
            )
        }
    }

    private func makeViewModel(
        completedCount: Int,
        personalOrder: Int?
    ) -> ClimbDetailViewModel {
        let viewModel = ClimbDetailViewModel(climb: .preview)
        viewModel.leaderboardSummary = LiveReplayLeaderboardSummary(
            totalClimbers: completedCount,
            completedCount: completedCount,
            personalBestDurationSeconds: nil,
            updatedAt: nil
        )

        if let personalOrder {
            viewModel.personalFinisherStatus = LiveReplayFinisherStatus(
                globalCompletionOrder: personalOrder,
                firstCompletedAt: nil,
                bestCompletionDurationSeconds: nil,
                updatedAt: nil
            )
        }

        return viewModel
    }
}
