import Foundation
import Testing
@testable import AscendApp

struct RoutineWindowCoachMarkTests {
    // MARK: - The copy

    /// "Drag the window to change which intervals you're viewing." - his sentence, split at its
    /// natural break so it fits the card's two slots, the same shape as "Drag a block." / "Up
    /// and down for the level."
    @Test
    func theCopyIsExactlyWhatWasDecided() {
        #expect(RoutineWindowCoachMark.title == "Drag the window.")
        #expect(RoutineWindowCoachMark.message == "Change which intervals you're viewing.")
        #expect(RoutineWindowCoachMark.presentation.title == RoutineWindowCoachMark.title)
        #expect(RoutineWindowCoachMark.presentation.message == RoutineWindowCoachMark.message)
    }

    /// Explanatory copy was rejected outright: the card does not teach the mechanic, name the
    /// threshold, or run to a second sentence.
    @Test
    func theCopyNamesNoThresholdAndAddsNoSecondSentence() {
        let message = RoutineWindowCoachMark.message

        #expect(message.filter { $0 == "." }.count == 1)
        #expect(message.allSatisfy { !$0.isNumber })
        #expect(RoutineWindowCoachMark.title.allSatisfy { !$0.isNumber })
    }

    /// His word is viewing, not editing.
    @Test
    func theCopySaysViewingRatherThanEditing() {
        #expect(RoutineWindowCoachMark.message.localizedStandardContains("viewing"))
        #expect(!RoutineWindowCoachMark.message.localizedStandardContains("editing"))
    }

    // MARK: - Not a fourth walkthrough step

    /// The first-open run is three marks driven by `allCases`, and it can never reach this one:
    /// a new routine cannot have eight intervals. A fourth case would add a dot to a sequence
    /// this mark never appears in.
    @Test
    func itIsNotAFourthStepOfTheFirstOpenWalkthrough() {
        #expect(RoutineBuilderCoachMark.allCases.count == 3)
        #expect(RoutineWindowCoachMark.presentation.stepCount == 1)
        #expect(RoutineWindowCoachMark.presentation.stepIndex == 0)
    }

    @Test
    func itCarriesASingleGotItRatherThanSkipAndNext() {
        #expect(RoutineWindowCoachMark.presentation.primaryActionTitle == "Got it")
        #expect(RoutineWindowCoachMark.presentation.showsSkip == false)
    }

    @Test
    func itKeepsItsOwnStorageKeySoNeitherRunCanDismissTheOther() {
        #expect(RoutineWindowCoachMark.seenStorageKey != RoutineBuilderCoachMark.seenStorageKey)
    }

    @Test
    func theWalkthroughStillCarriesItsThreeDotsAndItsSkip() {
        for mark in RoutineBuilderCoachMark.allCases {
            #expect(mark.presentation.stepCount == 3)
            #expect(mark.presentation.stepIndex == mark.rawValue)
            #expect(mark.presentation.showsSkip)
        }

        #expect(RoutineBuilderCoachMark.timeline.presentation.primaryActionTitle == "Next")
        #expect(RoutineBuilderCoachMark.add.presentation.primaryActionTitle == "Done")
    }

    // MARK: - When it fires

    @Test
    func itFiresTheFirstTimeARoutineOutgrowsTheScreen() {
        #expect(
            RoutineWindowCoachMark.shouldPresent(
                isWindowEngaged: true,
                hasSeen: false,
                isCoachMarkOnScreen: false
            )
        )
    }

    @Test
    func itNeverFiresWhileTheIntervalsStillFit() {
        #expect(
            RoutineWindowCoachMark.shouldPresent(
                isWindowEngaged: false,
                hasSeen: false,
                isCoachMarkOnScreen: false
            ) == false
        )
    }

    @Test
    func itFiresOnceAndThenNeverAgain() {
        #expect(
            RoutineWindowCoachMark.shouldPresent(
                isWindowEngaged: true,
                hasSeen: true,
                isCoachMarkOnScreen: false
            ) == false
        )
    }

    /// Opening a twelve-interval routine on a fresh device is the one place both runs come due
    /// at once. The walkthrough owns the screen until it is done, and this queues behind it.
    @Test
    func itNeverFiresOverAnotherCoachMark() {
        #expect(
            RoutineWindowCoachMark.shouldPresent(
                isWindowEngaged: true,
                hasSeen: false,
                isCoachMarkOnScreen: true
            ) == false
        )
    }

    // MARK: - What it spotlights

    @Test
    func itPointsAtTheOverviewAndNoWalkthroughStepDoes() {
        let walkthroughTargets = RoutineBuilderCoachMark.allCases.map(\.target)

        #expect(!walkthroughTargets.contains(.overview))
        #expect(Set(walkthroughTargets).count == walkthroughTargets.count)
    }
}
