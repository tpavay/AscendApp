import Foundation
import Testing
@testable import AscendApp

struct RoutineIntervalVoiceOverTests {
    /// The caption the design board specifies, in full:
    /// "Interval 2 of 5. Level 7, 4 minutes. Adjustable. Swipe up or down to change the level."
    /// VoiceOver supplies "Adjustable" from the adjustable action; the rest is ours.
    @Test
    func aBlockReadsBackTheWayTheBoardSpecifiesIt() {
        let interval = RoutineInterval(duration: 240, intensityValue: 7, order: 1)

        #expect(RoutineIntervalVoiceOver.label(position: 2, count: 5) == "Interval 2 of 5")
        #expect(RoutineIntervalVoiceOver.value(for: interval) == "Level 7, 4 minutes")
        #expect(RoutineIntervalVoiceOver.levelHint == "Swipe up or down to change the level.")
    }

    @Test
    func aStepTypeOtherThanStandardIsSpokenBecauseTheBlockMayBeTooNarrowToShowIt() {
        let interval = RoutineInterval(
            duration: 240,
            intensityValue: 6,
            modifiers: RoutineStepTypeOption.backward.modifiers,
            order: 2
        )

        #expect(RoutineIntervalVoiceOver.value(for: interval) == "Level 6, 4 minutes, Backward")
    }

    @Test
    func standardIsNotSpokenBecauseMostIntervalsAreStandard() {
        let interval = RoutineInterval(
            duration: 180,
            intensityValue: 16,
            modifiers: RoutineStepTypeOption.standard.modifiers,
            order: 0
        )

        #expect(RoutineIntervalVoiceOver.value(for: interval) == "Level 16, 3 minutes")
    }

    @Test
    func durationsAreSpokenAsWordsNotAsAClock() {
        #expect(RoutineIntervalVoiceOver.durationDescription(30) == "30 seconds")
        #expect(RoutineIntervalVoiceOver.durationDescription(60) == "1 minute")
        #expect(RoutineIntervalVoiceOver.durationDescription(240) == "4 minutes")
        #expect(RoutineIntervalVoiceOver.durationDescription(270) == "4 minutes 30 seconds")
        #expect(RoutineIntervalVoiceOver.durationDescription(1_800) == "30 minutes")
    }

    @Test
    func aBlockAtTheFloorStillReadsItsExactDurationEvenThoughItIsDrawnWider() {
        let interval = RoutineInterval(duration: 30, intensityValue: 20, order: 1)

        #expect(RoutineIntervalVoiceOver.value(for: interval) == "Level 20, 30 seconds")
    }

    /// Reorder by drag has no VoiceOver equivalent, so move earlier / move later stand in.
    /// These names are the rotor the board renders.
    @Test
    func theRotorCarriesEverythingTheSwipeCannot() {
        #expect(RoutineIntervalVoiceOver.Action.addTime == "Add 30 seconds")
        #expect(RoutineIntervalVoiceOver.Action.subtractTime == "Subtract 30 seconds")
        #expect(RoutineIntervalVoiceOver.Action.changeStepType == "Change step type")
        #expect(RoutineIntervalVoiceOver.Action.moveEarlier == "Move earlier")
        #expect(RoutineIntervalVoiceOver.Action.moveLater == "Move later")
        #expect(RoutineIntervalVoiceOver.Action.delete == "Delete interval")
    }
}
