import Foundation
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
