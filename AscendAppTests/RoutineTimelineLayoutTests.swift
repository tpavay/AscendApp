import CoreGraphics
import Foundation
import Testing
@testable import AscendApp

struct RoutineTimelineLayoutTests {
    /// The plot inside a 402pt device: 20pt screen padding and 14pt card padding each side.
    private let deviceContentWidth: CGFloat = 334

    // MARK: - Fit to width

    @Test
    func blocksAreDrawnInProportionToTheirDuration() {
        let widths = RoutineTimelineLayout.blockWidths(
            durations: [180, 240, 240, 180, 240],
            availableWidth: deviceContentWidth
        )

        let plotted = deviceContentWidth - RoutineTimelineLayout.blockSpacing * 4
        #expect(widths.count == 5)
        #expect(abs(widths.reduce(0, +) - plotted) < 0.01)
        // 3:00 against 4:00 in an 18-minute routine.
        #expect(abs(widths[0] / widths[1] - 0.75) < 0.001)
    }

    @Test
    func aBlockTooShortToHoldItsNumberIsWidenedToTheFloor() {
        // The hard case from the board: 5:00, 0:30, 5:00, 0:30, 19:00.
        let widths = RoutineTimelineLayout.blockWidths(
            durations: [300, 30, 300, 30, 1_140],
            availableWidth: deviceContentWidth
        )

        #expect(widths[1] == RoutineTimelineLayout.minimumBlockWidth)
        #expect(widths[3] == RoutineTimelineLayout.minimumBlockWidth)
        #expect(widths.allSatisfy { $0 >= RoutineTimelineLayout.minimumBlockWidth })
    }

    @Test
    func wideBlocksGiveUpExactlyWhatTheFlooredBlocksTake() {
        let durations: [TimeInterval] = [300, 30, 300, 30, 1_140]
        let widths = RoutineTimelineLayout.blockWidths(
            durations: durations,
            availableWidth: deviceContentWidth
        )

        let plotted = deviceContentWidth - RoutineTimelineLayout.blockSpacing * CGFloat(durations.count - 1)
        #expect(abs(widths.reduce(0, +) - plotted) < 0.01)
    }

    @Test
    func widiningOneBlockCanPushAnotherThroughTheFloorAndBothAreCaught() {
        // 0:30 is under the floor outright. 4:30 clears it at first pass and only falls
        // through once the 0:30 block has taken its width out of the pool.
        let durations: [TimeInterval] = [30, 270, 1_350, 1_350]
        let widths = RoutineTimelineLayout.blockWidths(
            durations: durations,
            availableWidth: deviceContentWidth
        )

        #expect(widths[0] == RoutineTimelineLayout.minimumBlockWidth)
        #expect(widths[1] == RoutineTimelineLayout.minimumBlockWidth)
        #expect(widths.allSatisfy { $0 >= RoutineTimelineLayout.minimumBlockWidth })

        let plotted = deviceContentWidth - RoutineTimelineLayout.blockSpacing * 3
        #expect(abs(widths.reduce(0, +) - plotted) < 0.01)
    }

    @Test
    func aSingleIntervalOwnsTheWholeStrip() {
        let widths = RoutineTimelineLayout.blockWidths(
            durations: [120],
            availableWidth: deviceContentWidth
        )

        #expect(widths == [deviceContentWidth])
    }

    @Test
    func moreBlocksThanTheFloorCanHoldShareWhatThereIsInsteadOfOverflowing() {
        let durations = Array(repeating: TimeInterval(30), count: 40)
        let widths = RoutineTimelineLayout.blockWidths(
            durations: durations,
            availableWidth: deviceContentWidth
        )

        let plotted = deviceContentWidth - RoutineTimelineLayout.blockSpacing * CGFloat(durations.count - 1)
        #expect(abs(widths.reduce(0, +) - plotted) < 0.01)
        #expect(widths.allSatisfy { $0 < RoutineTimelineLayout.minimumBlockWidth })
    }

    @Test
    func noIntervalsMeansNoBlocks() {
        #expect(RoutineTimelineLayout.blockWidths(durations: [], availableWidth: 334).isEmpty)
    }

    @Test
    func aPlotWithNoWidthYetDrawsNothingRatherThanNegativeBlocks() {
        let widths = RoutineTimelineLayout.blockWidths(durations: [120, 120], availableWidth: 0)
        #expect(widths == [0, 0])
    }

    // MARK: - Drag resolution

    @Test
    func aDragAcrossTheWholePlotSpansAllTwentyFiveLevels() {
        #expect(abs(RoutineTimelineLayout.pointsPerLevel(plotHeight: 210) - 8.4) < 0.001)
        #expect(abs(RoutineTimelineLayout.pointsPerLevel(plotHeight: 240) - 9.6) < 0.001)
    }

    @Test
    func shortRoutinesKeepTheBlockEdgeWeldedToTheFinger() {
        let contentWidth: CGFloat = 322

        // 18 minutes: 30 seconds is 8.9pt of travel, which is above the clamp.
        let eighteenMinutes = RoutineTimelineLayout.pointsPerDurationStep(
            contentWidth: contentWidth,
            totalDuration: 1_080
        )

        #expect(abs(eighteenMinutes - 8.94) < 0.01)
        #expect(eighteenMinutes > RoutineTimelineLayout.minimumPointsPerDurationStep)
    }

    @Test
    func longRoutinesClampSoOneThumbWidthNeverBuysMinutes() {
        let contentWidth: CGFloat = 322

        // Unclamped these would be 5.4pt and 2.7pt per 30 seconds.
        let thirtyMinutes = RoutineTimelineLayout.pointsPerDurationStep(
            contentWidth: contentWidth,
            totalDuration: 1_800
        )
        let sixtyMinutes = RoutineTimelineLayout.pointsPerDurationStep(
            contentWidth: contentWidth,
            totalDuration: 3_600
        )

        #expect(thirtyMinutes == RoutineTimelineLayout.minimumPointsPerDurationStep)
        #expect(sixtyMinutes == RoutineTimelineLayout.minimumPointsPerDurationStep)
    }

    @Test
    func theClampBitesWhereTrackingWouldFallUnderEightPoints() {
        let contentWidth: CGFloat = 322
        let threshold = contentWidth * 30 / RoutineTimelineLayout.minimumPointsPerDurationStep

        let justUnder = RoutineTimelineLayout.pointsPerDurationStep(
            contentWidth: contentWidth,
            totalDuration: threshold - 60
        )
        let justOver = RoutineTimelineLayout.pointsPerDurationStep(
            contentWidth: contentWidth,
            totalDuration: threshold + 60
        )

        #expect(justUnder > RoutineTimelineLayout.minimumPointsPerDurationStep)
        #expect(justOver == RoutineTimelineLayout.minimumPointsPerDurationStep)
    }

    // MARK: - Reorder

    @Test
    func aBlockDraggedLeftPastItsNeighbourLandsBeforeIt() {
        let widths: [CGFloat] = [60, 60, 60, 60, 60]

        let destination = RoutineTimelineLayout.reorderDestinationIndex(
            draggedIndex: 3,
            draggedCenterX: RoutineTimelineLayout.blockOriginX(at: 1, widths: widths) + 30,
            widths: widths
        )

        #expect(destination == 1)
    }

    @Test
    func aBlockDraggedRightPastItsNeighbourLandsAfterIt() {
        let widths: [CGFloat] = [60, 60, 60, 60, 60]

        let destination = RoutineTimelineLayout.reorderDestinationIndex(
            draggedIndex: 0,
            draggedCenterX: RoutineTimelineLayout.blockOriginX(at: 3, widths: widths) + 31,
            widths: widths
        )

        #expect(destination == 3)
    }

    @Test
    func aBlockThatHasNotMovedFarEnoughStaysWhereItIs() {
        let widths: [CGFloat] = [60, 60, 60, 60, 60]

        let destination = RoutineTimelineLayout.reorderDestinationIndex(
            draggedIndex: 2,
            draggedCenterX: RoutineTimelineLayout.blockOriginX(at: 2, widths: widths) + 30 + 8,
            widths: widths
        )

        #expect(destination == 2)
    }

    @Test
    func draggingPastEitherEndClampsToTheEnds() {
        let widths: [CGFloat] = [60, 60, 60]

        #expect(
            RoutineTimelineLayout.reorderDestinationIndex(
                draggedIndex: 2,
                draggedCenterX: -500,
                widths: widths
            ) == 0
        )
        #expect(
            RoutineTimelineLayout.reorderDestinationIndex(
                draggedIndex: 0,
                draggedCenterX: 900,
                widths: widths
            ) == 2
        )
    }

    // MARK: - What a block has room to say

    /// The movement caption is bottom-aligned and the level and clock are drawn from the top,
    /// so a short block has to drop the caption rather than draw it over the clock. A level-1
    /// block on the 210pt plot is 42pt tall; the collision only clears around level 4.
    @Test
    func aShortBlockDropsItsMovementCaptionRatherThanDrawingItOverTheClock() {
        let plotHeight: CGFloat = 210
        let height = { (level: Int) in plotHeight * RoutineIntervalScale.heightFraction(forLevel: level) }

        #expect(!RoutineTimelineLayout.showsMovementLabel(blockWidth: 120, blockHeight: height(1)))
        #expect(!RoutineTimelineLayout.showsMovementLabel(blockWidth: 120, blockHeight: height(2)))
        #expect(!RoutineTimelineLayout.showsMovementLabel(blockWidth: 120, blockHeight: height(3)))
        #expect(RoutineTimelineLayout.showsMovementLabel(blockWidth: 120, blockHeight: height(4)))
        #expect(RoutineTimelineLayout.showsMovementLabel(blockWidth: 120, blockHeight: height(25)))
    }

    @Test
    func aNarrowBlockDropsItsMovementCaptionHoweverTallItIs() {
        #expect(!RoutineTimelineLayout.showsMovementLabel(blockWidth: 28, blockHeight: 210))
        #expect(!RoutineTimelineLayout.showsMovementLabel(blockWidth: 55, blockHeight: 210))
        #expect(RoutineTimelineLayout.showsMovementLabel(blockWidth: 56, blockHeight: 210))
    }

    /// Anything wide enough for the caption is already wide enough for the clock, so the two
    /// gates can never disagree about which labels a block is drawing.
    @Test
    func theClockIsAlwaysDrawnOnABlockWideEnoughForItsMovementCaption() {
        #expect(!RoutineTimelineLayout.showsDurationClock(blockWidth: RoutineTimelineLayout.minimumBlockWidth))
        #expect(RoutineTimelineLayout.showsDurationClock(blockWidth: RoutineTimelineLayout.minimumMovementLabelWidth))
        #expect(RoutineTimelineLayout.minimumClockWidth <= RoutineTimelineLayout.minimumMovementLabelWidth)
    }

    @Test
    func blockOriginsAccountForTheGapsBetweenThem() {
        let widths: [CGFloat] = [40, 50, 60]

        #expect(RoutineTimelineLayout.blockOriginX(at: 0, widths: widths) == 0)
        #expect(RoutineTimelineLayout.blockOriginX(at: 1, widths: widths) == 40 + RoutineTimelineLayout.blockSpacing)
        #expect(
            RoutineTimelineLayout.blockOriginX(at: 2, widths: widths)
                == 90 + RoutineTimelineLayout.blockSpacing * 2
        )
    }
}
