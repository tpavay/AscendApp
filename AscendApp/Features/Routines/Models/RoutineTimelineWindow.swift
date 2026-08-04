import CoreGraphics
import Foundation

/// The working window: which slice of a long routine the builder draws at full size.
///
/// Fit to width is unchanged - it is applied to the window rather than to the whole routine, so
/// the number of intervals can never be what pushes a block under the tap-target minimum. The
/// window exists only while the routine cannot fit: it arrives on the interval that overflows
/// and leaves again the moment they fit, with no hysteresis on either side.
///
/// Pure maths, so the window can be reasoned about - and tested - without a view tree.
enum RoutineTimelineWindow {
    /// The smallest thing a finger can be asked to hit. This, not a chosen block count, is what
    /// decides how many blocks a strip holds: 334pt of plot holds seven.
    static let minimumTapTarget: CGFloat = 44

    /// How long a lifted block has to be held against an edge before the window takes another
    /// step. The finger has already run out of screen by then, so the hold is the only travel
    /// left to read.
    static let edgeAdvanceInterval: Duration = .milliseconds(300)

    /// How many blocks a strip of this width holds without the count alone putting one under
    /// the tap target. Each block needs its own width plus the gap that follows it, and the
    /// last block needs no trailing gap.
    static func capacity(availableWidth: CGFloat) -> Int {
        guard availableWidth > 0 else { return 0 }

        let slot = minimumTapTarget + RoutineTimelineLayout.blockSpacing
        let fitting = Int(((availableWidth + RoutineTimelineLayout.blockSpacing) / slot).rounded(.down))
        return max(fitting, 1)
    }

    /// Symmetric on purpose: the strip that arrives on the eighth interval goes again on the
    /// seventh, because seven fit. A strip that has not been measured yet engages nothing.
    static func isEngaged(intervalCount: Int, availableWidth: CGFloat) -> Bool {
        guard availableWidth > 0 else { return false }
        return intervalCount > capacity(availableWidth: availableWidth)
    }

    /// The intervals the builder draws, clamped into the routine. The whole routine while it
    /// still fits, so nothing below this has to know whether the window exists.
    static func visibleRange(startIndex: Int, intervalCount: Int, availableWidth: CGFloat) -> Range<Int> {
        guard intervalCount > 0 else { return 0..<0 }
        guard isEngaged(intervalCount: intervalCount, availableWidth: availableWidth) else {
            return 0..<intervalCount
        }

        let length = capacity(availableWidth: availableWidth)
        let start = min(max(startIndex, 0), intervalCount - length)
        return start..<(start + length)
    }

    /// The start that brings `index` on screen, moving as little as it can - one interval for a
    /// block dragged one past the edge, and nothing at all for one already in view.
    static func start(
        bringingIntoView index: Int,
        from currentStart: Int,
        intervalCount: Int,
        availableWidth: CGFloat
    ) -> Int {
        let range = visibleRange(
            startIndex: currentStart,
            intervalCount: intervalCount,
            availableWidth: availableWidth
        )
        guard isEngaged(intervalCount: intervalCount, availableWidth: availableWidth) else { return 0 }

        let length = range.count
        let lastStart = max(intervalCount - length, 0)
        let target = min(max(index, 0), intervalCount - 1)

        if target < range.lowerBound { return target }
        if target >= range.upperBound { return min(target - length + 1, lastStart) }
        return range.lowerBound
    }

    /// Where the window sits over the overview, as fractions of the routine's length. The
    /// overview is drawn on the time axis, so the window has to be too - seven long intervals
    /// cover more of it than seven short ones.
    static func span(durations: [TimeInterval], range: Range<Int>) -> ClosedRange<Double> {
        let total = durations.reduce(0, +)
        guard total > 0, !range.isEmpty else { return 0...1 }

        let bounded = range.clamped(to: durations.indices)
        guard !bounded.isEmpty else { return 0...1 }

        let before = durations[..<bounded.lowerBound].reduce(0, +)
        let through = durations[..<bounded.upperBound].reduce(0, +)

        let start = min(max(before / total, 0), 1)
        let end = min(max(through / total, start), 1)
        return start...end
    }

    /// Where a drag on the overview lands: the interval start nearest the fraction the finger
    /// has carried the window's leading edge to.
    static func start(
        forLeadingFraction fraction: Double,
        durations: [TimeInterval],
        availableWidth: CGFloat
    ) -> Int {
        let count = durations.count
        guard isEngaged(intervalCount: count, availableWidth: availableWidth) else { return 0 }

        let lastStart = count - capacity(availableWidth: availableWidth)
        let total = durations.reduce(0, +)
        guard total > 0 else {
            return min(max(Int((fraction * Double(count)).rounded()), 0), lastStart)
        }

        var nearest = 0
        var nearestDistance = Double.greatestFiniteMagnitude
        var elapsed: TimeInterval = 0

        for index in 0...lastStart {
            let distance = abs(elapsed / total - fraction)
            if distance < nearestDistance {
                nearestDistance = distance
                nearest = index
            }
            elapsed += durations[index]
        }

        return nearest
    }

    /// Which way a lifted block held past the end of the window walks it, if at all. Without
    /// this a long routine could only ever be reordered inside one window's neighbourhood.
    static func edgeAdvance(
        draggedCenterX: CGFloat,
        widths: [CGFloat],
        range: Range<Int>,
        intervalCount: Int
    ) -> Int {
        guard let firstWidth = widths.first, let lastWidth = widths.last else { return 0 }

        let lastCenter = RoutineTimelineLayout.blockOriginX(at: widths.count - 1, widths: widths)
            + lastWidth / 2

        if draggedCenterX > lastCenter, range.upperBound < intervalCount { return 1 }
        if draggedCenterX < firstWidth / 2, range.lowerBound > 0 { return -1 }
        return 0
    }
}
