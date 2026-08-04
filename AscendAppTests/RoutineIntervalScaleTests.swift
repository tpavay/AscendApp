import Foundation
import SwiftUI
import Testing
@testable import AscendApp

struct RoutineIntervalScaleTests {
    @Test
    func levelOneIsTheFloorOfTheScaleAndLevelTwentyFiveTheTop() {
        #expect(RoutineIntervalScale.normalizedLevel(1) == 0)
        #expect(RoutineIntervalScale.normalizedLevel(25) == 1)
        #expect(RoutineIntervalScale.heightFraction(forLevel: 1) == 0.2)
        #expect(RoutineIntervalScale.heightFraction(forLevel: 25) == 1.0)
    }

    /// Height by level on 25 steps, not by tier on five - the whole point being that level 16
    /// and level 20 stopped drawing the same bar.
    @Test
    func everyLevelDrawsItsOwnHeight() {
        let fractions = RoutineIntervalScale.levelRange.map {
            RoutineIntervalScale.heightFraction(forLevel: $0)
        }

        #expect(Set(fractions).count == RoutineIntervalScale.levelRange.count)
        #expect(zip(fractions, fractions.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test
    func heightsMatchTheProportionsTheBoardWasDrawnAt() {
        let expected: [Int: Double] = [1: 0.2, 4: 0.3, 6: 0.3667, 7: 0.4, 8: 0.4333, 12: 0.5667, 16: 0.7, 20: 0.8333]

        for (level, fraction) in expected {
            #expect(abs(RoutineIntervalScale.heightFraction(forLevel: level) - fraction) < 0.0005)
        }
    }

    @Test
    func levelsOutsideTheScaleClampInsteadOfDrawingOffThePlot() {
        #expect(RoutineIntervalScale.heightFraction(forLevel: 0) == 0.2)
        #expect(RoutineIntervalScale.heightFraction(forLevel: -8) == 0.2)
        #expect(RoutineIntervalScale.heightFraction(forLevel: 99) == 1.0)
    }

    // MARK: - Colour

    /// The divergence this scale exists to end: on the five-bucket tier, level 16 and level 20
    /// were the same hue, so one routine drew two ways depending on the screen.
    @Test
    @MainActor
    func everyLevelColoursItsOwnBarRatherThanItsTiersBucket() {
        let resolved = RoutineIntervalScale.levelRange.map {
            RoutineIntervalScale.color(forLevel: $0, colorScheme: .dark).resolve(in: EnvironmentValues())
        }

        #expect(Set(resolved).count == RoutineIntervalScale.levelRange.count)
        #expect(resolved[15] != resolved[19])
    }

    /// Colour and height read the same normalisation, so a taller bar is always a hotter one.
    @Test
    @MainActor
    func colourAndHeightMoveTogetherUpTheScale() {
        for level in RoutineIntervalScale.levelRange {
            let fromLevel = RoutineIntervalScale.color(forLevel: level, colorScheme: .dark)
            let fromNormalized = RoutineIntervalScale.color(
                forNormalizedLevel: RoutineIntervalScale.normalizedLevel(level),
                colorScheme: .dark
            )

            #expect(fromLevel.resolve(in: EnvironmentValues()) == fromNormalized.resolve(in: EnvironmentValues()))
        }
    }

    @Test
    func anIntervalColoursAndSizesFromItsOwnResolvedLevel() {
        let interval = RoutineInterval(duration: 120, intensityValue: 16, order: 0)

        #expect(RoutineIntervalScale.normalizedLevel(of: interval) == RoutineIntervalScale.normalizedLevel(16))
        #expect(RoutineIntervalScale.heightFraction(of: interval) == RoutineIntervalScale.heightFraction(forLevel: 16))
    }

    // MARK: - Routine average

    /// The routine's colour is weighted by time held - a 30-second spike must not colour a
    /// routine the way a ten-minute block does.
    @Test
    func theRoutineAverageIsWeightedByHowLongEachLevelIsHeld() {
        let intervals = [
            RoutineInterval(duration: 600, intensityValue: 5, order: 0),
            RoutineInterval(duration: 30, intensityValue: 25, order: 1)
        ]

        let average = RoutineIntervalScale.normalizedAverageLevel(of: intervals)
        let unweighted = (RoutineIntervalScale.normalizedLevel(5) + RoutineIntervalScale.normalizedLevel(25)) / 2

        #expect(average < unweighted)
        #expect(abs(average - (RoutineIntervalScale.normalizedLevel(5) * 600 + 30) / 630) < 0.0001)
    }

    @Test
    func aRoutineWithNoIntervalsAveragesToTheFloorInsteadOfDividingByZero() {
        #expect(RoutineIntervalScale.normalizedAverageLevel(of: []) == 0)
    }

    // MARK: - Duration grid

    @Test
    func durationsSnapToTheThirtySecondGridTheModelAlreadyStores() {
        #expect(RoutineIntervalScale.snappedDuration(119) == 120)
        #expect(RoutineIntervalScale.snappedDuration(136) == 150)
        #expect(RoutineIntervalScale.snappedDuration(120) == 120)
    }

    @Test
    func aDragCannotTakeAnIntervalBelowThirtySecondsOrPastThirtyMinutes() {
        #expect(RoutineIntervalScale.snappedDuration(0) == 30)
        #expect(RoutineIntervalScale.snappedDuration(-600) == 30)
        #expect(RoutineIntervalScale.snappedDuration(4_000) == 1_800)
    }

    @Test
    func everySnappedDurationIsOnTheStoredStride() {
        let stored = Set(stride(from: 30.0, through: 1_800.0, by: 30.0))

        for seconds in stride(from: -100.0, through: 2_000.0, by: 7.0) {
            #expect(stored.contains(RoutineIntervalScale.snappedDuration(seconds)))
        }
    }
}
