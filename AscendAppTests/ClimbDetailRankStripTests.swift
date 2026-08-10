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
        let renderer = ImageRenderer(
            content: ClimbDetailHeroCardFront(
                climb: .preview,
                subtitle: Climb.preview.displayLocation,
                stripOrderText: nil
            ) {
                Color.red
            }
            .frame(width: 353, height: 390)
            .clipShape(RoundedRectangle(cornerRadius: 28))
        )
        renderer.scale = 2

        let image = try #require(renderer.uiImage, "ImageRenderer produced no hero artwork")
        let bitmap = try #require(image.cgImage, "The hero render had no bitmap")
        let pixels = try rgbaPixels(from: bitmap)
        let y = bitmap.height / 2
        let inset = 8
        let sampledX = inset..<(bitmap.width - inset)
        let artworkPixelCount = sampledX.count(where: { x in
            let offset = ((y * bitmap.width) + x) * 4
            return pixels[offset] > 150
                && pixels[offset + 1] < 30
                && pixels[offset + 2] < 30
                && pixels[offset + 3] > 240
        })

        #expect(
            Double(artworkPixelCount) / Double(sampledX.count) > 0.98,
            "The artwork should reach both hero-card edges without a reserved 48pt strip"
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
