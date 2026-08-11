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
    private static let renderScale: CGFloat = 2

    private static let artworkMarker = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)

    private struct HeroMidRow {
        let pixels: [UInt8]
        let scale: CGFloat

        func artworkRatio(fromPoint: CGFloat, toPoint: CGFloat) -> Double {
            let sampled = Int(fromPoint * scale)..<Int(toPoint * scale)
            let artworkPixelCount = sampled.count(where: { x in
                let offset = x * 4
                return pixels[offset] > 150
                    && pixels[offset + 1] < 30
                    && pixels[offset + 2] < 30
                    && pixels[offset + 3] > 240
            })

            return Double(artworkPixelCount) / Double(sampled.count)
        }
    }

    private func renderHeroMidRow(stripOrderText: String?) throws -> HeroMidRow {
        let renderer = ImageRenderer(
            content: ClimbDetailHeroCardFront(
                climb: .preview,
                subtitle: Climb.preview.displayLocation,
                stripOrderText: stripOrderText
            ) {
                Self.artworkMarker
            }
            .frame(width: Self.heroWidth, height: Self.heroHeight)
            .clipShape(RoundedRectangle(cornerRadius: 28))
        )
        renderer.scale = Self.renderScale

        let image = try #require(renderer.uiImage, "ImageRenderer produced no hero artwork")
        let bitmap = try #require(image.cgImage, "The hero render had no bitmap")
        let pixels = try rgbaPixels(from: bitmap)
        let y = bitmap.height / 2
        let rowStart = y * bitmap.width * 4

        return HeroMidRow(
            pixels: Array(pixels[rowStart..<(rowStart + bitmap.width * 4)]),
            scale: Self.renderScale
        )
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

    private func rgbaPixels(from bitmap: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: bitmap.width * bitmap.height * 4)

        try pixels.withUnsafeMutableBytes { bytes in
            let context = try #require(
                CGContext(
                    data: bytes.baseAddress,
                    width: bitmap.width,
                    height: bitmap.height,
                    bitsPerComponent: 8,
                    bytesPerRow: bitmap.width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ),
                "Could not create a bitmap context for the hero render"
            )
            context.draw(
                bitmap,
                in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height)
            )
        }

        return pixels
    }
}
