import CoreGraphics
import Testing
@testable import AscendApp

/// Where the `BEST` marker may draw inside a row that carries content.
///
/// Production drew the marker through the captain's name on 2026-09-26. The
/// rule this pins: the line passes behind content with clearance around it, and
/// the word is only drawn where it touches no content and fits in the row.
struct LiveReplayPreviousBestMarkerLayoutTests {
    /// The captain's live row: 370pt wide, 74pt tall, his name and `YOU` chip
    /// centred on the row's height, his avatar and step count either side.
    private let rowSize = CGSize(width: 370, height: 74)
    private let avatar = CGRect(x: 48, y: 15, width: 44, height: 44)
    private let name = CGRect(x: 102, y: 26, width: 118, height: 22)
    private let chip = CGRect(x: 227, y: 30, width: 33, height: 15)
    private let stepCount = CGRect(x: 298, y: 22, width: 68, height: 30)
    private let flagSize = CGSize(width: 22, height: 9.75)

    private var content: [CGRect] { [avatar, name, chip, stepCount] }

    private func layout(
        at x: CGFloat,
        placement: LiveReplayPreviousBestMarkerLayout.LabelPlacement = .top,
        labelSize: CGSize? = nil,
        obstacles: [CGRect]? = nil
    ) -> LiveReplayPreviousBestMarkerLayout {
        LiveReplayPreviousBestMarkerLayout(
            size: rowSize,
            progress: x / rowSize.width,
            lineWidth: 2,
            labelSize: labelSize ?? flagSize,
            labelPlacement: placement,
            obstacles: obstacles ?? content
        )
    }

    // MARK: - The line

    @Test
    func theLinePassesBehindTheNameWithClearanceEitherSide() {
        let marker = layout(at: 194)

        #expect(marker.lineSegments == [0...22, 52...74])
        for segment in marker.lineSegments {
            #expect(segment.upperBound <= name.minY - LiveReplayPreviousBestMarkerLayout.clearance
                || segment.lowerBound >= name.maxY + LiveReplayPreviousBestMarkerLayout.clearance)
        }
    }

    @Test
    func theLineRunsTheFullHeightWhereNothingIsInTheWay() {
        #expect(layout(at: 280).lineSegments == [0...74])
    }

    /// A line that only grazes the clearance around content still breaks there -
    /// the clearance is part of the rule, not a rounding margin.
    @Test
    func theLineBreaksInsideTheClearanceToo() {
        let marker = layout(at: name.maxX + 3)

        #expect(marker.lineSegments == [0...22, 52...74])
    }

    /// Under the avatar the line keeps only the slivers of margin above and
    /// below it, and a sliver too short to read as a line is dropped.
    @Test
    func theLineKeepsOnlyReadablePiecesAroundTheAvatar() {
        let marker = layout(at: 70)

        #expect(marker.lineSegments == [0...11, 63...74])

        let crowded = LiveReplayPreviousBestMarkerLayout(
            size: CGSize(width: 370, height: 50),
            progress: 70.0 / 370.0,
            lineWidth: 2,
            labelSize: flagSize,
            labelPlacement: .top,
            obstacles: [CGRect(x: 48, y: 3, width: 44, height: 44)]
        )
        #expect(crowded.lineSegments.isEmpty)
    }

    // MARK: - The word

    @Test
    func theFlagFliesAboveTheNameInTheRowsTopMargin() {
        let marker = layout(at: 194)

        #expect(marker.showsLabel)
        #expect(marker.labelFrame.minX == 195 + LiveReplayPreviousBestMarkerLayout.labelSpacing)
        #expect(marker.labelFrame.minY == LiveReplayPreviousBestMarkerLayout.labelTopInset)
        #expect(marker.labelFrame.maxY < name.minY)
    }

    @Test
    func theFlagStillFitsAboveTheAvatar() {
        #expect(layout(at: 60).showsLabel)
    }

    /// The captain's 2026-09-01 rule, kept: beside the step count the word
    /// gets out of the number's way and the line stays.
    @Test
    func theWordIsWithheldWhereItWouldTouchTheStepCount() {
        let tallStepCount = CGRect(x: 298, y: 4, width: 68, height: 66)
        let marker = layout(at: 290, obstacles: [avatar, name, chip, tallStepCount])

        #expect(marker.showsLabel == false)
        #expect(marker.lineSegments == [0...74])
    }

    @Test
    func theWordIsWithheldWhereItWouldRunOffTheRow() {
        let marker = layout(at: 360, obstacles: [])

        #expect(marker.showsLabel == false)
    }

    /// Before the word has been measured its frame is empty and touches
    /// nothing, so it would pass every check and flash in before being withheld.
    @Test(arguments: [CGSize.zero, CGSize(width: 22, height: 0), CGSize(width: 0, height: 9.75)])
    func anUnmeasuredWordIsWithheld(labelSize: CGSize) {
        let nearTheEnd = layout(at: 360, labelSize: labelSize, obstacles: [])

        #expect(nearTheEnd.showsLabel == false)
        #expect(layout(at: 194, labelSize: labelSize).showsLabel == false)
    }

    /// The vertical word the 2026-09-01 design centred on the line is exactly
    /// what cut through the name. Centred on the row, it is withheld there.
    @Test
    func aCentredVerticalWordIsNeverDrawnOverTheName() {
        let marker = layout(at: 194, placement: .centered, labelSize: CGSize(width: 7, height: 36))

        #expect(marker.showsLabel == false)
    }

    /// The Just Me summit bar has no content inside it: the whole line and the
    /// vertical word draw exactly as they always have, until the trailing margin.
    @Test
    func aHostWithNoContentKeepsTheWholeMarker() {
        let bar = CGSize(width: 300, height: 22)
        let marker = LiveReplayPreviousBestMarkerLayout(
            size: bar,
            progress: 0.5,
            lineWidth: 2,
            labelSize: CGSize(width: 7, height: 36),
            labelPlacement: .centered,
            trailingInset: 40
        )

        #expect(marker.lineSegments == [0...22])
        #expect(marker.showsLabel)
        #expect(marker.labelFrame.midY == 11)

        let nearTheEnd = LiveReplayPreviousBestMarkerLayout(
            size: bar,
            progress: 0.9,
            lineWidth: 2,
            labelSize: CGSize(width: 7, height: 36),
            labelPlacement: .centered,
            trailingInset: 40
        )
        #expect(nearTheEnd.showsLabel == false)
        #expect(nearTheEnd.lineSegments == [0...22])
    }
}
