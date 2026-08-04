import CoreGraphics
import Foundation
import Testing
@testable import AscendApp

struct RoutineTimelineWindowTests {
    /// The plot inside a 402pt device: 20pt screen padding and 14pt card padding each side.
    private let deviceContentWidth: CGFloat = 334

    /// The shipped, featured HIIT Sprint: 1:00 warm-up, ten 0:30 bursts, 1:00 down. Twelve
    /// intervals, which is why this work exists at all.
    private let hiitSprint: [TimeInterval] = [60] + Array(repeating: 30, count: 10) + [60]

    // MARK: - How many blocks a strip holds

    @Test
    func aDeviceWidthStripHoldsSevenBlocksAtTheTapTarget() {
        #expect(RoutineTimelineWindow.capacity(availableWidth: deviceContentWidth) == 7)
    }

    /// The number falls out of the tap target, not the other way round: (334 + 3) / (44 + 3).
    @Test
    func theCapacityIsWhateverTheTapTargetAllows() {
        let capacity = RoutineTimelineWindow.capacity(availableWidth: deviceContentWidth)
        let slot = RoutineTimelineWindow.minimumTapTarget + RoutineTimelineLayout.blockSpacing

        #expect(CGFloat(capacity) * slot - RoutineTimelineLayout.blockSpacing <= deviceContentWidth)
        #expect(CGFloat(capacity + 1) * slot - RoutineTimelineLayout.blockSpacing > deviceContentWidth)
    }

    @Test
    func aStripThatHasNotBeenMeasuredYetHoldsNothing() {
        #expect(RoutineTimelineWindow.capacity(availableWidth: 0) == 0)
        #expect(RoutineTimelineWindow.isEngaged(intervalCount: 40, availableWidth: 0) == false)
    }

    @Test
    func aStripTooNarrowForOneBlockStillDrawsOne() {
        #expect(RoutineTimelineWindow.capacity(availableWidth: 20) == 1)
    }

    // MARK: - The threshold, arriving and leaving

    @Test
    func theWindowArrivesOnTheEighthIntervalAndNotBefore() {
        for count in 1...7 {
            #expect(RoutineTimelineWindow.isEngaged(intervalCount: count, availableWidth: deviceContentWidth) == false)
        }
        #expect(RoutineTimelineWindow.isEngaged(intervalCount: 8, availableWidth: deviceContentWidth))
    }

    /// Symmetric, as decided: delete back to seven and it goes, because seven fit again. No
    /// hysteresis - the boundary is the same number in both directions.
    @Test
    func theWindowLeavesAgainAtSeven() {
        let width = deviceContentWidth

        #expect(RoutineTimelineWindow.isEngaged(intervalCount: 8, availableWidth: width))
        #expect(RoutineTimelineWindow.isEngaged(intervalCount: 7, availableWidth: width) == false)
        #expect(RoutineTimelineWindow.isEngaged(intervalCount: 8, availableWidth: width))
    }

    @Test
    func theShippedHIITSprintOutgrowsTheScreen() {
        #expect(RoutineTimelineWindow.isEngaged(intervalCount: hiitSprint.count, availableWidth: deviceContentWidth))
    }

    // MARK: - What the window shows

    @Test
    func theWholeRoutineIsTheRangeWhileItStillFits() {
        #expect(
            RoutineTimelineWindow.visibleRange(startIndex: 0, intervalCount: 5, availableWidth: deviceContentWidth)
                == 0..<5
        )
    }

    @Test
    func anEmptyRoutineHasAnEmptyRange() {
        #expect(
            RoutineTimelineWindow.visibleRange(startIndex: 0, intervalCount: 0, availableWidth: deviceContentWidth)
                .isEmpty
        )
    }

    @Test
    func theWindowIsAlwaysSevenBlocksLongHoweverLongTheRoutineIs() {
        for count in 8...40 {
            let range = RoutineTimelineWindow.visibleRange(
                startIndex: 0,
                intervalCount: count,
                availableWidth: deviceContentWidth
            )
            #expect(range.count == 7)
        }
    }

    @Test
    func aStartPastTheEndIsPulledBackSoTheWindowStaysFull() {
        let range = RoutineTimelineWindow.visibleRange(
            startIndex: 99,
            intervalCount: 12,
            availableWidth: deviceContentWidth
        )

        #expect(range == 5..<12)
    }

    @Test
    func aNegativeStartIsPulledForward() {
        #expect(
            RoutineTimelineWindow.visibleRange(startIndex: -4, intervalCount: 12, availableWidth: deviceContentWidth)
                == 0..<7
        )
    }

    // MARK: - The tap target the window exists for

    /// The claim the whole design rests on: however long the routine gets, the count is never
    /// what puts a block under a fingertip. Duration ratios inside a window still meet the
    /// pre-existing width floor, which this deliberately does not change.
    @Test
    func noBlockInAWindowFallsUnderTheTapTargetBecauseOfTheCount() {
        for count in 8...40 {
            let range = RoutineTimelineWindow.visibleRange(
                startIndex: 0,
                intervalCount: count,
                availableWidth: deviceContentWidth
            )
            let widths = RoutineTimelineLayout.blockWidths(
                durations: Array(repeating: 120, count: range.count),
                availableWidth: deviceContentWidth
            )

            #expect(widths.allSatisfy { $0 >= RoutineTimelineWindow.minimumTapTarget })
        }
    }

    /// What the same routine draws without a window, for contrast: past eleven intervals the
    /// floor gives up and every block is drawn identically whatever its duration.
    @Test
    func theSameRoutineWithoutAWindowLosesBothItsTapTargetAndItsDurations() {
        let unwindowed = RoutineTimelineLayout.blockWidths(
            durations: hiitSprint,
            availableWidth: deviceContentWidth
        )

        #expect(unwindowed.allSatisfy { $0 < RoutineTimelineWindow.minimumTapTarget })
        // The 1:00 warm-up and the 0:30 sprints are drawn the same width.
        #expect(abs(unwindowed[0] - unwindowed[1]) < 0.001)
    }

    /// And with the window, the same routine draws its minute-long blocks wider than its
    /// half-minute ones again, because seven blocks never reach the floor.
    @Test
    func theWindowGivesTheHIITSprintItsDurationsBack() {
        let range = RoutineTimelineWindow.visibleRange(
            startIndex: 0,
            intervalCount: hiitSprint.count,
            availableWidth: deviceContentWidth
        )
        let widths = RoutineTimelineLayout.blockWidths(
            durations: Array(hiitSprint[range]),
            availableWidth: deviceContentWidth
        )

        #expect(widths[0] > widths[1] * 1.9)
        #expect(widths.allSatisfy { $0 >= RoutineTimelineLayout.minimumBlockWidth })
    }

    // MARK: - Following a block

    @Test
    func aBlockAlreadyOnScreenMovesNothing() {
        #expect(
            RoutineTimelineWindow.start(
                bringingIntoView: 3,
                from: 0,
                intervalCount: 12,
                availableWidth: deviceContentWidth
            ) == 0
        )
    }

    /// A block dragged one past the trailing edge moves the window exactly one, never a jump.
    @Test
    func aBlockOnePastTheEdgeMovesTheWindowExactlyOne() {
        #expect(
            RoutineTimelineWindow.start(
                bringingIntoView: 7,
                from: 0,
                intervalCount: 12,
                availableWidth: deviceContentWidth
            ) == 1
        )
        #expect(
            RoutineTimelineWindow.start(
                bringingIntoView: 4,
                from: 5,
                intervalCount: 12,
                availableWidth: deviceContentWidth
            ) == 4
        )
    }

    /// The rule the captain confirmed: after + Add Interval the window follows the new block,
    /// which lands last. A new block is Standard at level 1 and exists to be dragged.
    @Test
    func addingAnEighthIntervalPutsTheWindowOnIt() {
        let start = RoutineTimelineWindow.start(
            bringingIntoView: 7,
            from: 0,
            intervalCount: 8,
            availableWidth: deviceContentWidth
        )

        #expect(start == 1)
        #expect(
            RoutineTimelineWindow.visibleRange(
                startIndex: start,
                intervalCount: 8,
                availableWidth: deviceContentWidth
            ) == 1..<8
        )
    }

    @Test
    func followingABlockNeverRunsPastEitherEndOfTheRoutine() {
        for index in 0..<12 {
            let start = RoutineTimelineWindow.start(
                bringingIntoView: index,
                from: 0,
                intervalCount: 12,
                availableWidth: deviceContentWidth
            )
            #expect(start >= 0)
            #expect(start <= 12 - 7)
        }
    }

    @Test
    func nothingToFollowWhileTheRoutineStillFits() {
        #expect(
            RoutineTimelineWindow.start(
                bringingIntoView: 4,
                from: 0,
                intervalCount: 5,
                availableWidth: deviceContentWidth
            ) == 0
        )
    }

    // MARK: - Where the window sits on the overview

    /// The overview is drawn on the time axis, so the window has to be too: seven long
    /// intervals cover more of it than seven short ones.
    @Test
    func theWindowCoversTheTimeItsIntervalsTakeNotAnEqualShareOfTheStrip() {
        // 1:00, then ten 0:30, then 1:00 - seven minutes of routine.
        let span = RoutineTimelineWindow.span(durations: hiitSprint, range: 0..<7)

        #expect(span.lowerBound == 0)
        // 60 + 6 * 30 of 420 seconds.
        #expect(abs(span.upperBound - 240.0 / 420.0) < 0.0001)
    }

    @Test
    func theWindowSitsWhereItsFirstIntervalStarts() {
        let span = RoutineTimelineWindow.span(durations: hiitSprint, range: 5..<12)

        #expect(abs(span.lowerBound - 180.0 / 420.0) < 0.0001)
        #expect(span.upperBound == 1)
    }

    @Test
    func aWindowOverTheWholeRoutineCoversTheWholeOverview() {
        let span = RoutineTimelineWindow.span(durations: [120, 120, 120], range: 0..<3)

        #expect(span == 0...1)
    }

    @Test
    func aRoutineWithNoTimeInItStillProducesADrawableSpan() {
        #expect(RoutineTimelineWindow.span(durations: [], range: 0..<0) == 0...1)
        #expect(RoutineTimelineWindow.span(durations: [0, 0], range: 0..<1) == 0...1)
    }

    // MARK: - Dragging the overview

    @Test
    func draggingTheOverviewLandsOnTheIntervalStartNearestTheFinger() {
        let durations = Array(repeating: TimeInterval(120), count: 20)

        #expect(
            RoutineTimelineWindow.start(
                forLeadingFraction: 0,
                durations: durations,
                availableWidth: deviceContentWidth
            ) == 0
        )
        // Half way along a twenty-interval routine is interval ten.
        #expect(
            RoutineTimelineWindow.start(
                forLeadingFraction: 0.5,
                durations: durations,
                availableWidth: deviceContentWidth
            ) == 10
        )
    }

    @Test
    func draggingPastEitherEndOfTheOverviewStopsAtTheEnd() {
        let durations = Array(repeating: TimeInterval(120), count: 20)

        #expect(
            RoutineTimelineWindow.start(
                forLeadingFraction: -3,
                durations: durations,
                availableWidth: deviceContentWidth
            ) == 0
        )
        #expect(
            RoutineTimelineWindow.start(
                forLeadingFraction: 4,
                durations: durations,
                availableWidth: deviceContentWidth
            ) == 20 - 7
        )
    }

    /// A pyramid of unequal intervals is the case the time axis exists for: the fraction has to
    /// resolve through the durations, not through the index.
    @Test
    func draggingResolvesThroughTheDurationsRatherThanTheIndex() {
        var durations = Array(repeating: TimeInterval(30), count: 15)
        durations[0] = 600

        // The first interval alone is over half the routine's length.
        #expect(
            RoutineTimelineWindow.start(
                forLeadingFraction: 0.55,
                durations: durations,
                availableWidth: deviceContentWidth
            ) == 1
        )
    }

    @Test
    func thereIsNowhereToDragAWindowThatDoesNotExist() {
        #expect(
            RoutineTimelineWindow.start(
                forLeadingFraction: 0.9,
                durations: Array(repeating: 120, count: 5),
                availableWidth: deviceContentWidth
            ) == 0
        )
    }

    // MARK: - Walking the window with a lifted block

    private var sevenEqualWidths: [CGFloat] {
        RoutineTimelineLayout.blockWidths(
            durations: Array(repeating: 120, count: 7),
            availableWidth: deviceContentWidth
        )
    }

    /// Without this a twenty-interval routine could only ever be reordered inside one window's
    /// neighbourhood - a capability lost silently rather than a visual change.
    @Test
    func aBlockHeldPastTheLastVisibleBlockWalksTheWindowForward() {
        let widths = sevenEqualWidths
        let pastTheEnd = deviceContentWidth + 20

        #expect(
            RoutineTimelineWindow.edgeAdvance(
                draggedCenterX: pastTheEnd,
                widths: widths,
                range: 0..<7,
                intervalCount: 20
            ) == 1
        )
    }

    @Test
    func aBlockHeldPastTheFirstVisibleBlockWalksTheWindowBack() {
        #expect(
            RoutineTimelineWindow.edgeAdvance(
                draggedCenterX: -20,
                widths: sevenEqualWidths,
                range: 6..<13,
                intervalCount: 20
            ) == -1
        )
    }

    @Test
    func theWindowStopsWalkingAtEitherEndOfTheRoutine() {
        let widths = sevenEqualWidths

        #expect(
            RoutineTimelineWindow.edgeAdvance(
                draggedCenterX: deviceContentWidth + 20,
                widths: widths,
                range: 13..<20,
                intervalCount: 20
            ) == 0
        )
        #expect(
            RoutineTimelineWindow.edgeAdvance(
                draggedCenterX: -20,
                widths: widths,
                range: 0..<7,
                intervalCount: 20
            ) == 0
        )
    }

    /// A block resting inside the window is not held against anything, so nothing walks.
    @Test
    func aBlockInsideTheWindowLeavesItWhereItIs() {
        let widths = sevenEqualWidths

        for index in widths.indices {
            let center = RoutineTimelineLayout.blockOriginX(at: index, widths: widths) + widths[index] / 2
            #expect(
                RoutineTimelineWindow.edgeAdvance(
                    draggedCenterX: center,
                    widths: widths,
                    range: 6..<13,
                    intervalCount: 20
                ) == 0
            )
        }
    }

    @Test
    func anUnmeasuredStripWalksNothing() {
        #expect(
            RoutineTimelineWindow.edgeAdvance(
                draggedCenterX: 200,
                widths: [],
                range: 0..<0,
                intervalCount: 20
            ) == 0
        )
    }
}
