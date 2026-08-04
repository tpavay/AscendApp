import Foundation
import SwiftUI
import Testing
import UIKit
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

/// The spotlight is only a spotlight if the overlay can still find the thing it points at. The
/// overview's target is the one that is not a sibling of the others - it is emitted *inside*
/// the subtree the walkthrough's timeline target wraps - so this renders the real nesting and
/// reads the resolved anchors back, which a hardcoded `targetRect` cannot do.
@MainActor
struct RoutineBuilderCoachMarkAnchorTests {
    @Test
    func aTargetNestedInsideAnotherOneStillResolves() throws {
        let resolved = try Self.resolveTargets {
            VStack(spacing: 0) {
                Color.clear
                    .frame(width: 300, height: 44)
                    .routineCoachMarkTarget(.overview)

                Color.clear
                    .frame(width: 300, height: 200)
            }
            .routineCoachMarkTarget(.timeline)
        }

        let overview = try #require(
            resolved[.overview],
            "The nested overview target was dropped - the window coach mark would draw with no spotlight"
        )
        let timeline = try #require(resolved[.timeline], "The wrapping timeline target was dropped")

        #expect(overview.height == 44)
        #expect(timeline.height == 244)
        // The overview is inside the timeline, so the timeline's bounds have to contain it.
        #expect(timeline.contains(overview))
    }

    /// The three walkthrough targets are siblings, and they still all arrive - the merge that
    /// keeps the nested one must not have cost the flat ones.
    @Test
    func siblingTargetsAllStillArrive() throws {
        let resolved = try Self.resolveTargets {
            VStack(spacing: 0) {
                Color.clear.frame(width: 300, height: 200).routineCoachMarkTarget(.timeline)
                Color.clear.frame(width: 300, height: 44).routineCoachMarkTarget(.stepControl)
                Color.clear.frame(width: 300, height: 44).routineCoachMarkTarget(.add)
            }
        }

        #expect(Set(resolved.keys) == [.timeline, .stepControl, .add])
    }

    /// Renders the probe through the same `ImageRenderer` the evidence tests use, which runs a
    /// real layout pass, and reports what `overlayPreferenceValue` actually received.
    private static func resolveTargets(
        @ViewBuilder content: () -> some View
    ) throws -> [RoutineBuilderCoachMarkTarget: CGRect] {
        let recorder = AnchorRecorder()

        let probe = content()
            .overlayPreferenceValue(RoutineBuilderCoachMarkAnchorKey.self) { anchors in
                GeometryReader { proxy in
                    AnchorReporter(
                        recorder: recorder,
                        rects: anchors.mapValues { proxy[$0] }
                    )
                }
            }
            .frame(width: 402, height: 874)

        let renderer = ImageRenderer(content: probe)
        _ = try #require(renderer.uiImage, "ImageRenderer produced no image")

        return try #require(recorder.rects, "The coach mark overlay was never handed any anchors")
    }
}

@MainActor
private final class AnchorRecorder {
    var rects: [RoutineBuilderCoachMarkTarget: CGRect]?
}

/// Reports from `body`, because `ImageRenderer` evaluates bodies but runs no lifecycle.
@MainActor
private struct AnchorReporter: View {
    let recorder: AnchorRecorder
    let rects: [RoutineBuilderCoachMarkTarget: CGRect]

    var body: some View {
        let _ = { recorder.rects = rects }()
        Color.clear
    }
}
