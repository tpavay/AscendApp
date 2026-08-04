import SwiftUI

/// How a routine interval's level becomes a drawn block, and what the drag gestures are
/// allowed to write back. Height and colour both come off the level on 25 steps, so a
/// block at level 16 never draws the same as a block at level 20.
///
/// Every surface that draws an interval - the builder timeline, the list card and thumbnail
/// charts, the detail rows, the routine hero and the live session bar - reads this type, so
/// one routine can never show two hues across screens.
enum RoutineIntervalScale {
    static let levelRange = 1...25

    /// The stored duration grid, unchanged: `stride(from: 30, through: 1800, by: 30)`.
    static let durationStep: TimeInterval = 30
    static let durationRange: ClosedRange<TimeInterval> = 30...1800

    /// Level 1 maps to 0 and level 25 to 1 - the same normalisation `SegmentedHeatmapSlider`
    /// uses, so a block and the slider agree on colour for the same level.
    static func normalizedLevel(_ level: Int) -> Double {
        let span = Double(levelRange.upperBound - levelRange.lowerBound)
        return Double(SPMMappingService.clampedLevel(level) - levelRange.lowerBound) / span
    }

    static func normalizedLevel(of interval: RoutineInterval) -> Double {
        normalizedLevel(interval.resolvedLevel)
    }

    /// The routine's level as one number, weighted by how long it is held - a 30-second
    /// spike does not colour a whole routine the way a ten-minute block does.
    static func normalizedAverageLevel(of intervals: [RoutineInterval]) -> Double {
        let weighted = intervals.reduce(into: (level: 0.0, duration: 0.0)) { result, interval in
            let duration = max(interval.duration, 0)
            result.level += normalizedLevel(of: interval) * duration
            result.duration += duration
        }

        guard weighted.duration > 0 else {
            guard !intervals.isEmpty else { return 0 }
            return intervals.reduce(0) { $0 + normalizedLevel(of: $1) } / Double(intervals.count)
        }
        return weighted.level / weighted.duration
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

    static func clampedDuration(_ duration: TimeInterval) -> TimeInterval {
        min(max(duration, durationRange.lowerBound), durationRange.upperBound)
    }

    /// Durations only ever exist on the 30-second grid, whatever a drag lands on.
    static func snappedDuration(_ duration: TimeInterval) -> TimeInterval {
        clampedDuration((duration / durationStep).rounded() * durationStep)
    }
}
