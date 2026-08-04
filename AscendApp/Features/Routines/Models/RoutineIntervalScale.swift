import SwiftUI

/// How a routine interval's level becomes a drawn block, and what the drag gestures are
/// allowed to write back. Height and colour both come off the level on 25 steps, so a
/// block at level 16 never draws the same as a block at level 20.
///
/// Anything that draws a routine's intensity - a block, a bar, a segment, a ridge, or a
/// card's accent stripe - takes its colour, its height and its average from here, so one
/// routine can never show two hues across screens.
enum RoutineIntervalScale {
    static let levelRange = 1...25

    /// The stored duration grid, unchanged: `stride(from: 30, through: 1800, by: 30)`.
    static let durationStep: TimeInterval = 30
    static let durationRange: ClosedRange<TimeInterval> = 30...1800

    /// Level 1 maps to 0 and level 25 to 1 - the same normalisation `SegmentedHeatmapSlider`
    /// uses, so a block and the slider agree on colour for the same level.
    static func normalized(level: Double) -> Double {
        let lower = Double(levelRange.lowerBound)
        let upper = Double(levelRange.upperBound)
        return (min(max(level, lower), upper) - lower) / (upper - lower)
    }

    static func normalizedLevel(_ level: Int) -> Double {
        normalized(level: Double(SPMMappingService.clampedLevel(level)))
    }

    static func normalizedLevel(of interval: RoutineInterval) -> Double {
        normalizedLevel(interval.resolvedLevel)
    }

    /// The routine as one level, weighted by how long each level is held - a 30-second spike
    /// does not move it the way a ten-minute block does. The only definition of a routine's
    /// average: the builder header, the card stripes and the hero all read it.
    static func averageLevel(of intervals: [RoutineInterval]) -> Double {
        let weighted = intervals.reduce(into: (level: 0.0, duration: 0.0)) { result, interval in
            let duration = max(interval.duration, 0)
            result.level += Double(interval.resolvedLevel) * duration
            result.duration += duration
        }

        if weighted.duration > 0 {
            return weighted.level / weighted.duration
        }

        guard !intervals.isEmpty else { return Double(levelRange.lowerBound) }
        return intervals.reduce(0.0) { $0 + Double($1.resolvedLevel) } / Double(intervals.count)
    }

    static func roundedAverageLevel(of intervals: [RoutineInterval]) -> Int {
        Int(averageLevel(of: intervals).rounded())
    }

    static func normalizedAverageLevel(of intervals: [RoutineInterval]) -> Double {
        normalized(level: averageLevel(of: intervals))
    }

    /// Level 1 keeps a fifth of the plot so the lightest interval still reads as a block;
    /// level 25 fills it.
    static func heightFraction(forLevel level: Int) -> Double {
        0.2 + normalizedLevel(level) * 0.8
    }

    static func heightFraction(of interval: RoutineInterval) -> Double {
        heightFraction(forLevel: interval.resolvedLevel)
    }

    static func color(forLevel level: Int, colorScheme: ColorScheme) -> Color {
        color(forNormalizedLevel: normalizedLevel(level), colorScheme: colorScheme)
    }

    static func color(of interval: RoutineInterval, colorScheme: ColorScheme) -> Color {
        color(forLevel: interval.resolvedLevel, colorScheme: colorScheme)
    }

    static func color(forNormalizedLevel value: Double, colorScheme: ColorScheme) -> Color {
        Color.heatMapColor(for: value, colorScheme: colorScheme)
    }

    /// The routine's one hue, for anything that colours the routine rather than an interval.
    static func averageColor(of intervals: [RoutineInterval], colorScheme: ColorScheme) -> Color {
        color(forNormalizedLevel: normalizedAverageLevel(of: intervals), colorScheme: colorScheme)
    }

    static func clampedDuration(_ duration: TimeInterval) -> TimeInterval {
        min(max(duration, durationRange.lowerBound), durationRange.upperBound)
    }

    /// Durations only ever exist on the 30-second grid, whatever a drag lands on.
    static func snappedDuration(_ duration: TimeInterval) -> TimeInterval {
        clampedDuration((duration / durationStep).rounded() * durationStep)
    }
}
