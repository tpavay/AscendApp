import CoreGraphics
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// What the captain saw on the shipped build: with the window engaged, the strip carried two
/// nested lime rounded outlines - the coach mark's spotlight ring around the whole strip, and
/// inside it the working window itself. A box in a box, with the tip obscuring the one element
/// it existed to name.
///
/// These read the drawn pixels rather than the view tree, because "one outline, not two" is a
/// claim about what lands on the screen. A row of pixels crossing the strip crosses two lime
/// runs when there is one outline and four when there are two, so the count is the finding.
@MainActor
struct RoutineCoachMarkSpotlightRingTests {
    /// A twenty-interval pyramid, so the window is a slice in the middle of the ridge with
    /// clear air either side of it - a flush window edge and a ring edge would be one run.
    private var pyramid: [RoutineInterval] {
        (0..<20).map { index in
            RoutineInterval(
                duration: 120,
                intensityValue: index < 10 ? 5 + index * 2 : 23 - (index - 10) * 2,
                order: index
            )
        }
    }

    /// The eighth interval is where the overview arrives, so this is the first routine that can
    /// ever show this mark.
    private var eightIntervals: [RoutineInterval] {
        let levels = [6, 22, 8, 22, 8, 18, 8, 22]
        return levels.enumerated().map { index, level in
            RoutineInterval(duration: index == 0 ? 60 : 30, intensityValue: level, order: index)
        }
    }

    // MARK: - The fix

    @Test
    func theWindowMarkLeavesExactlyOneLimeOutlineOnTheStrip() throws {
        let pixels = try RenderedStrip(
            intervals: pyramid,
            visibleRange: 6..<13,
            presentation: RoutineWindowCoachMark.presentation
        )

        #expect(
            pixels.widestLimeCrossing == 2,
            "The strip should carry the working window's outline and nothing else"
        )
        #expect(pixels.hasLime, "The working window's own outline must survive - it is the real UI")
    }

    /// The threshold routine, not just the long one: eight intervals is the first count that can
    /// raise this mark at all.
    @Test
    func theStripStaysSingleOutlinedAtTheEighthInterval() throws {
        #expect(RoutineTimelineWindow.isEngaged(intervalCount: 8, availableWidth: 334))

        let pixels = try RenderedStrip(
            intervals: eightIntervals,
            visibleRange: 1..<8,
            presentation: RoutineWindowCoachMark.presentation
        )

        #expect(pixels.widestLimeCrossing == 2)
        #expect(pixels.hasLime)
    }

    /// The defect itself, so the count above is measuring something real: the same mark with the
    /// ring left on draws the four crossings the captain photographed.
    @Test
    func theSameMarkWithItsRingLeftOnDrawsTheNestedPair() throws {
        let pixels = try RenderedStrip(
            intervals: pyramid,
            visibleRange: 6..<13,
            presentation: RoutineCoachMarkPresentation(
                title: RoutineWindowCoachMark.title,
                message: RoutineWindowCoachMark.message,
                stepCount: 1,
                stepIndex: 0,
                primaryActionTitle: "Got it",
                showsSkip: false,
                drawsSpotlightRing: true
            )
        )

        #expect(
            pixels.widestLimeCrossing == 4,
            "Two nested outlines are four lime crossings - this is what was removed"
        )
    }

    // MARK: - Nothing else changed

    /// His explicit constraint. The three walkthrough marks point at controls that carry no
    /// outline of their own, so each one keeps its ring - drawn here over the same strip, which
    /// is the only surface with a lime outline underneath to count against.
    @Test(arguments: RoutineBuilderCoachMark.allCases)
    func everyWalkthroughMarkStillDrawsItsRing(_ mark: RoutineBuilderCoachMark) throws {
        let pixels = try RenderedStrip(
            intervals: pyramid,
            visibleRange: 6..<13,
            presentation: mark.presentation
        )

        #expect(
            pixels.widestLimeCrossing == 4,
            "\(mark) lost its spotlight ring - the opt-out reached the shared default"
        )
    }

    @Test
    func theRingIsTheSharedDefaultAndOnlyTheWindowMarkOptsOut() {
        for mark in RoutineBuilderCoachMark.allCases {
            #expect(mark.presentation.drawsSpotlightRing)
        }

        #expect(RoutineWindowCoachMark.presentation.drawsSpotlightRing == false)

        // A presentation that says nothing about the ring draws it: the seam is an opt-out, not
        // a new thing every mark has to remember to ask for.
        let unstated = RoutineCoachMarkPresentation(
            title: "Anything.",
            message: "Anything at all.",
            stepCount: 1,
            stepIndex: 0,
            primaryActionTitle: "Got it",
            showsSkip: false
        )
        #expect(unstated.drawsSpotlightRing)
    }

    /// Dropping the ring must not dim the thing it was ringing: the punch-out is a separate
    /// mechanism, and the strip stays lit under the backdrop either way.
    @Test
    func theStripStaysLitUnderTheDimWithoutTheRing() throws {
        let withoutOverlay = try RenderedStrip(
            intervals: pyramid,
            visibleRange: 6..<13,
            presentation: nil
        )
        let withOverlay = try RenderedStrip(
            intervals: pyramid,
            visibleRange: 6..<13,
            presentation: RoutineWindowCoachMark.presentation
        )

        // Dimmed rather than punched out, the window's #86D30A would fall to (46, 72, 3) and stop
        // reading as lime at all, so this is the difference between all of it and none of it.
        #expect(withOverlay.limePixelCount >= withoutOverlay.limePixelCount * 9 / 10)
        #expect(withoutOverlay.limePixelCount > 0)
    }
}

/// One rendered strip, and the lime it carries.
///
/// Lime is read as the accent's green dominance (`#86D30A`), which nothing else on this surface
/// has: the ridge is drawn from the heat map, which is red at every level, and the label is grey.
@MainActor
private struct RenderedStrip {
    /// The strip's bounds inside the device, which is also the rect the overlay spotlights - in
    /// the app it is the anchor `RoutineTimelineOverview` publishes.
    static let strip = CGRect(x: 34, y: 200, width: 334, height: 62)
    static let device = CGSize(width: 402, height: 874)

    /// The band the counting runs over: the spotlight rect, which is the strip plus the overlay's
    /// own 4pt inset. Anything the card draws sits well below it.
    private static var band: CGRect { strip.insetBy(dx: -4, dy: -4) }

    private static let scale = 3

    private let width: Int
    private let height: Int
    private let bytes: [UInt8]

    init(
        intervals: [RoutineInterval],
        visibleRange: Range<Int>,
        presentation: RoutineCoachMarkPresentation?
    ) throws {
        let probe = ZStack(alignment: .topLeading) {
            Color.black

            RoutineTimelineOverview(
                intervals: intervals,
                visibleRange: visibleRange,
                onScrub: { _ in },
                onStep: { _ in },
                onScrubbingChange: { _ in }
            )
            .frame(width: Self.strip.width, height: Self.strip.height, alignment: .top)
            .offset(x: Self.strip.minX, y: Self.strip.minY)

            if let presentation {
                RoutineBuilderCoachMarkOverlay(
                    presentation: presentation,
                    targetRect: Self.strip,
                    containerSize: Self.device,
                    onNext: {},
                    onSkip: {}
                )
            }
        }
        .frame(width: Self.device.width, height: Self.device.height)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: probe)
        renderer.scale = CGFloat(Self.scale)

        let image = try #require(renderer.uiImage, "ImageRenderer produced no image")
        let bitmap = try #require(image.cgImage, "The render carried no bitmap")

        let pixelWidth = bitmap.width
        let pixelHeight = bitmap.height
        width = pixelWidth
        height = pixelHeight

        var buffer = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        try buffer.withUnsafeMutableBytes { raw in
            let context = try #require(
                CGContext(
                    data: raw.baseAddress,
                    width: pixelWidth,
                    height: pixelHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: pixelWidth * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ),
                "Could not open a bitmap over the render"
            )
            context.draw(bitmap, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        }
        bytes = buffer
    }

    /// The most lime runs any single row of the band crosses. Two nested outlines put four
    /// vertical strokes in a row's path; one outline puts two.
    var widestLimeCrossing: Int {
        rows.map(limeRunCount(inRow:)).max() ?? 0
    }

    var limePixelCount: Int {
        rows.reduce(0) { total, y in
            columns.reduce(total) { $0 + (isLime(x: $1, y: y) ? 1 : 0) }
        }
    }

    var hasLime: Bool {
        limePixelCount > 0
    }

    private var rows: Range<Int> {
        pixelRange(from: Self.band.minY, to: Self.band.maxY, limit: height)
    }

    private var columns: Range<Int> {
        pixelRange(from: Self.band.minX, to: Self.band.maxX, limit: width)
    }

    private func pixelRange(from lower: CGFloat, to upper: CGFloat, limit: Int) -> Range<Int> {
        let start = max(Int(lower) * Self.scale, 0)
        let end = min(Int(upper.rounded(.up)) * Self.scale, limit)
        return start..<max(start, end)
    }

    private func limeRunCount(inRow y: Int) -> Int {
        var runs = 0
        var wasLime = false

        for x in columns {
            let lime = isLime(x: x, y: y)
            if lime, !wasLime {
                runs += 1
            }
            wasLime = lime
        }

        return runs
    }

    private func isLime(x: Int, y: Int) -> Bool {
        let offset = (y * width + x) * 4
        let red = Int(bytes[offset])
        let green = Int(bytes[offset + 1])
        let blue = Int(bytes[offset + 2])

        // #86D30A is (134, 211, 10): bright, green-dominant, almost no blue. The heat map's
        // reds are all red-dominant, so nothing else in the band can pass this.
        return green > 128 && green > red * 13 / 10 && blue < 90
    }
}
