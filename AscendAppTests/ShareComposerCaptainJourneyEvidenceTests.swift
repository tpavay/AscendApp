import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Walks the exact sequence the captain reported, through the shipping
/// `ShareComposerViewModel`, and photographs what the canvas looks like at every
/// step when `ASCEND_EVIDENCE_DIR` is set.
///
/// Nothing here is a stand-in: the steps are the view model calls the composer's
/// controls make, and each frame is `ShareExportCanvas` - the same view the
/// exporter renders, so these images are what lands in the shared photo. The
/// comparisons read the canvas at 1x through `RenderedScreen` and keep only the
/// pixels, never a bitmap.
///
/// Rendering full canvases holds the main actor, so this takes the same gate the
/// window-hosting suites do.
@MainActor
@Suite(.hostsAWindow)
struct ShareComposerCaptainJourneyEvidenceTests {
    /// "I move a stat's label to the left, then add more stats and stack them
    /// vertically - and the label jumps back to the top."
    @Test
    func aLabelMovedLeftStaysLeftAfterAddingStatsAndStacking() throws {
        let viewModel = Self.makeViewModel()

        // 1. Place a steps sticker and move its label to the left.
        viewModel.addSticker(kind: .steps)
        let id = try #require(viewModel.selectedID)
        viewModel.setLabelPlacement(.leading, for: id)
        try Self.photograph(viewModel, named: "journey-1-label-moved-left")

        // 2. Add two more metrics and switch to the vertical stack.
        viewModel.toggleStat(ShareStatRef(kind: .duration), for: id)
        viewModel.toggleStat(ShareStatRef(kind: .calories), for: id)
        viewModel.setLayout(.column, for: id)
        let stacked = try Self.render(viewModel)
        try Self.photograph(viewModel, named: "journey-2-stacked-label-still-left")

        let sticker = try #require(viewModel.stickers.first)
        #expect(sticker.labelPlacement == .leading, "the label jumped back")
        #expect(sticker.statRefs.count == 3)
        #expect(sticker.layout == .column)

        // The same three stacked metrics with the label back on top must not be
        // the same picture - that identical render is what the captain saw.
        viewModel.setLabelPlacement(.above, for: id)
        let above = try Self.render(viewModel)
        try Self.photograph(viewModel, named: "journey-2b-same-stack-label-above")
        #expect(
            Self.differingPixelFraction(stacked, above) > 0.001,
            "a leading label rendered identically to an above label"
        )
    }

    /// "When I add the date, it literally says 'date' underneath it."
    @Test
    func theDateStickerCarriesNoLabelWhileAStepCountKeepsItsOwn() throws {
        let viewModel = Self.makeViewModel()
        viewModel.addSticker(kind: .date)
        viewModel.stickers[0].position = CGPoint(x: 0.5, y: 0.35)
        viewModel.addSticker(kind: .steps)
        viewModel.stickers[1].position = CGPoint(x: 0.5, y: 0.55)

        let canvas = try Self.render(viewModel)
        try Self.photograph(viewModel, named: "journey-3-date-has-no-label")

        // The rule, not an exception for the date: suppressing labels outright
        // changes nothing about the date, because it never had one - while the
        // step count beside it loses its unit.
        let dateID = viewModel.stickers[0].id
        viewModel.setLabelPlacement(.none, for: dateID)
        let dateSuppressed = try Self.render(viewModel)
        #expect(
            Self.differingPixelFraction(canvas, dateSuppressed) == 0,
            "the date drew a label"
        )

        viewModel.setLabelPlacement(.none, for: viewModel.stickers[1].id)
        let bothSuppressed = try Self.render(viewModel)
        try Self.photograph(viewModel, named: "journey-3b-labels-suppressed")
        #expect(
            Self.differingPixelFraction(dateSuppressed, bothSuppressed) > 0.0001,
            "the step count lost its label"
        )
    }

    /// Dragging a sticker onto the trash removes it, and the view model tells the
    /// view it did so the removal can be animated rather than popping.
    @Test
    func draggingOntoTheTrashRemovesTheStickerAndReportsIt() throws {
        let viewModel = Self.makeViewModel()
        viewModel.addSticker(kind: .steps)
        viewModel.addSticker(kind: .calories)
        let doomed = try #require(viewModel.stickers.last?.id)

        let before = try Self.render(viewModel)
        try Self.photograph(viewModel, named: "journey-4-two-stickers")

        viewModel.isOverTrash = true
        // Dropped onto the trash zone the composer draws at the bottom of the canvas.
        let trash = viewModel.trashRect(in: Self.canvasSize)
        let deleted = viewModel.handleDragEnded(
            id: doomed,
            center: CGPoint(x: trash.midX, y: trash.midY),
            canvasSize: Self.canvasSize
        )
        #expect(deleted, "the view was not told to animate the removal")
        #expect(viewModel.stickers.count == 1)
        #expect(viewModel.isOverTrash == false, "the trash stayed lit after the drop")

        let after = try Self.render(viewModel)
        try Self.photograph(viewModel, named: "journey-5-after-trash-delete")
        #expect(Self.differingPixelFraction(before, after) > 0.001)
    }

    // MARK: - Fixtures

    private static let canvasSize = CGSize(width: 390, height: 694)
    private static let workoutDate = Date(timeIntervalSince1970: 1_750_300_000)

    private static func makeViewModel() -> ShareComposerViewModel {
        ShareComposerViewModel(
            workout: Workout(
                name: "Live Climb",
                date: workoutDate,
                duration: 1_330,
                steps: 2_096,
                floors: Workout.stepsToFloors(2_096, stepsPerFloor: 16),
                caloriesBurned: 317,
                source: .headphoneMotion
            ),
            measurementSystem: .imperial,
            stepHeight: MeasurementSystem.imperial.defaultStepHeight,
            climbName: "Empire State Building",
            climbRank: 7,
            climbRankTotal: 2_460
        )
    }

    // MARK: - Rendering

    private static func canvas(_ viewModel: ShareComposerViewModel) -> some View {
        ShareExportCanvas(viewModel: viewModel, size: canvasSize)
    }

    /// The canvas as the composer currently holds it, read at 1x: every comparison
    /// here is "did the picture change", which a colour answers at any scale.
    private static func render(_ viewModel: ShareComposerViewModel) throws -> [RGBA] {
        try RenderedScreen.withOffscreenPixels(of: canvas(viewModel)) { pixels in
            pixels.pixels(in: CGRect(origin: .zero, size: pixels.size))
        }
    }

    private static func photograph(_ viewModel: ShareComposerViewModel, named name: String) throws {
        try RenderedScreen.photograph(canvas(viewModel), named: "share-composer-\(name)")
    }

    /// Fraction of pixels that differ between two same-sized reads of the canvas.
    private static func differingPixelFraction(_ lhs: [RGBA], _ rhs: [RGBA]) -> Double {
        let count = max(lhs.count, rhs.count)
        guard count > 0 else { return 0 }
        var differing = abs(lhs.count - rhs.count)
        for (left, right) in zip(lhs, rhs) where left != right {
            differing += 1
        }
        return Double(differing) / Double(count)
    }
}
