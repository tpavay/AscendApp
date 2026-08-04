import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Visual evidence for the timeline editor, rendered from the real components rather than a
/// reproduction: `RoutineEditorStatsRow`, `RoutineTimelineEditor` and `RoutineStepTypeControl`
/// take plain values, so a renderer can flatten them without the Firebase-gated screen around
/// them.
///
/// The live editor is presented from a sheet behind auth, so this is the only way to put the
/// drawn result in front of a reviewer.
@MainActor
struct RoutineTimelineEditorSnapshotTests {
    /// The plot inside a 402pt device: 20pt screen padding and 14pt card padding each side.
    private let plotWidth: CGFloat = 334

    /// The routine the design board is drawn with.
    private var boardRoutine: [RoutineInterval] {
        [
            RoutineInterval(duration: 180, intensityValue: 16, order: 0),
            RoutineInterval(duration: 240, intensityValue: 7, order: 1),
            RoutineInterval(
                duration: 240,
                intensityValue: 6,
                modifiers: RoutineStepTypeOption.backward.modifiers,
                order: 2
            ),
            RoutineInterval(duration: 180, intensityValue: 20, order: 3),
            RoutineInterval(duration: 240, intensityValue: 4, order: 4)
        ]
    }

    /// The case the width floor exists for: 5:00, 0:30, 5:00, 0:30, 19:00.
    private var hardRoutine: [RoutineInterval] {
        [
            RoutineInterval(duration: 300, intensityValue: 7, order: 0),
            RoutineInterval(duration: 30, intensityValue: 20, order: 1),
            RoutineInterval(duration: 300, intensityValue: 7, order: 2),
            RoutineInterval(duration: 30, intensityValue: 20, order: 3),
            RoutineInterval(duration: 1_140, intensityValue: 6, order: 4)
        ]
    }

    /// The shipped, featured HIIT Sprint: 1:00 warm-up, ten 0:30 bursts, 1:00 down.
    private var hiitSprint: [RoutineInterval] {
        let levels = [6, 22, 8, 22, 8, 18, 8, 22, 8, 18, 8, 6]
        return levels.enumerated().map { index, level in
            RoutineInterval(
                duration: index == 0 || index == levels.count - 1 ? 60 : 30,
                intensityValue: level,
                order: index
            )
        }
    }

    /// A twenty-interval pyramid: no two neighbours alike, so nothing about it collapses.
    private var pyramid: [RoutineInterval] {
        (0..<20).map { index in
            RoutineInterval(
                duration: 120,
                intensityValue: index < 10 ? 5 + index * 2 : 23 - (index - 10) * 2,
                order: index
            )
        }
    }

    @Test
    func theEditorRendersAsTheBoardDrawsIt() throws {
        try renderEvidence(
            named: "routine-builder-screen",
            content: EditorSurface(intervals: boardRoutine, selectedIndex: 0)
        )
    }

    @Test
    func shortBlocksHoldTheirNumberAtTheWidthFloor() throws {
        try renderEvidence(
            named: "routine-builder-width-floor",
            content: EditorSurface(intervals: hardRoutine, selectedIndex: 4)
        )
    }

    @Test
    func anEmptyRoutineShowsTheGhostShape() throws {
        try renderEvidence(
            named: "routine-builder-empty",
            content: EditorSurface(intervals: [], selectedIndex: nil)
        )
    }

    @Test
    func theWalkthroughSpotlightsTheTimeline() throws {
        // A whole device, so the spotlight and the card are measured against the screen the
        // climber actually sees rather than against a crop.
        let device = CGSize(width: 402, height: 874)

        try renderEvidence(
            named: "routine-builder-coach-mark",
            content: ZStack(alignment: .top) {
                Color.black

                EditorSurface(intervals: boardRoutine, selectedIndex: 0)

                RoutineBuilderCoachMarkOverlay(
                    presentation: RoutineBuilderCoachMark.timeline.presentation,
                    targetRect: CGRect(x: 20, y: 78, width: 362, height: 262),
                    containerSize: device,
                    onNext: {},
                    onSkip: {}
                )
            }
            .frame(width: device.width, height: device.height)
        )
    }

    /// The routine this work exists for: twelve intervals, shipped and featured, which the
    /// unwindowed timeline drew as twelve identical 25pt blocks.
    @Test
    func theShippedHIITSprintIsUsable() throws {
        try renderEvidence(
            named: "routine-builder-long-routine",
            content: EditorSurface(intervals: hiitSprint, selectedIndex: 0)
        )
    }

    /// The whole routine above and the window below, on the routine the captain named: a
    /// twenty-interval pyramid, where nothing groups and every interval differs from its
    /// neighbour.
    @Test
    func aTwentyIntervalPyramidKeepsItsWholeShapeOnScreen() throws {
        try renderEvidence(
            named: "routine-builder-pyramid-window",
            content: EditorSurface(intervals: pyramid, selectedIndex: 9)
        )
    }

    /// The threshold, both sides of it in one frame. Seven intervals fit, so the screen carries
    /// no navigation at all; the eighth brings the overview. Symmetric, as decided: deleting
    /// back to seven is this same pair read right to left.
    @Test
    func theOverviewArrivesWithTheEighthIntervalAndLeavesWithoutIt() throws {
        let sevenFit = Array(hiitSprint.prefix(7))
        let eightDoNot = Array(hiitSprint.prefix(8))

        #expect(RoutineTimelineWindow.isEngaged(intervalCount: sevenFit.count, availableWidth: 334) == false)
        #expect(RoutineTimelineWindow.isEngaged(intervalCount: eightDoNot.count, availableWidth: 334))

        try renderEvidence(
            named: "routine-builder-threshold",
            content: HStack(alignment: .top, spacing: 0) {
                CaptionedSurface(caption: "7 INTERVALS - THEY FIT, NO OVERVIEW", intervals: sevenFit)
                CaptionedSurface(caption: "8 INTERVALS - THE OVERVIEW ARRIVES", intervals: eightDoNot)
            }
            .background(Color.black)
        )
    }

    /// The whole interaction, frame by frame: the drag resolves through the same
    /// `RoutineTimelineWindow.start(forLeadingFraction:)` the overview's gesture calls, so each
    /// row is the window a climber lands on holding their finger at that point of the ridge.
    @Test
    func draggingTheOverviewCarriesTheWindowAcrossTheRoutine() throws {
        let durations = pyramid.map(\.duration)
        // The last one is past the end on purpose: the window stops on the final seven rather
        // than running off it.
        let fractions: [Double] = [0, 0.25, 0.5, 1]

        let frames = fractions.map { fraction in
            let start = RoutineTimelineWindow.start(
                forLeadingFraction: fraction,
                durations: durations,
                availableWidth: plotWidth
            )
            return (
                fraction: fraction,
                range: RoutineTimelineWindow.visibleRange(
                    startIndex: start,
                    intervalCount: pyramid.count,
                    availableWidth: plotWidth
                )
            )
        }

        // The drag has to actually travel, and it has to stop on the last seven rather than
        // running off the end.
        #expect(frames.first?.range == 0..<7)
        #expect(frames.last?.range == 13..<20)
        #expect(Set(frames.map(\.range.lowerBound)).count == frames.count)

        try renderEvidence(
            named: "routine-builder-overview-drag",
            content: VStack(alignment: .leading, spacing: 18) {
                ForEach(frames, id: \.fraction) { frame in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FINGER AT \(Int(frame.fraction * 100))% - VIEWING INTERVALS \(frame.range.lowerBound + 1)-\(frame.range.upperBound)")
                            .font(.montserratSemiBold(size: 10))
                            .tracking(0.8)
                            .foregroundStyle(Color.accent)

                        RoutineTimelineOverview(
                            intervals: pyramid,
                            visibleRange: frame.range,
                            onScrub: { _ in },
                            onStep: { _ in },
                            onScrubbingChange: { _ in }
                        )
                        .frame(width: plotWidth)
                    }
                }
            }
            .padding(20)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        )
    }

    /// The one-off mark, spotlighting the overview rather than the timeline, with a single
    /// dot and a single Got it.
    @Test
    func theWindowCoachMarkSpotlightsTheOverview() throws {
        let device = CGSize(width: 402, height: 874)

        try renderEvidence(
            named: "routine-builder-window-coach-mark",
            content: ZStack(alignment: .top) {
                Color.black

                EditorSurface(intervals: hiitSprint, selectedIndex: 0)

                RoutineBuilderCoachMarkOverlay(
                    presentation: RoutineWindowCoachMark.presentation,
                    // The overview's own bounds on this surface: the card's content inset, and
                    // the label plus the ridge it labels.
                    targetRect: CGRect(x: 34, y: 88, width: 334, height: 58),
                    containerSize: device,
                    onNext: {},
                    onSkip: {}
                )
            }
            .frame(width: device.width, height: device.height)
        )
    }

    @Test
    func theStepRowShowsTheSelectedBlocksStepType() throws {
        try renderEvidence(
            named: "routine-builder-step-row",
            content: VStack(spacing: 12) {
                RoutineStepTypeRowLabel(stepType: .standard)
                RoutineStepTypeRowLabel(stepType: .faceRight)
            }
            .padding(20)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        )
    }

    private func renderEvidence(named name: String, content: some View) throws {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3

        let image = try #require(renderer.uiImage, "ImageRenderer produced no image")
        let png = try #require(image.pngData(), "UIImage produced no PNG data")

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        try png.write(to: URL(filePath: directory).appending(path: "\(name).png"))

        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
        #expect(png.count > 5_000)
    }
}

/// One editor surface with a caption above it, so two of them read as a before and an after.
private struct CaptionedSurface: View {
    let caption: String
    let intervals: [RoutineInterval]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(caption)
                .font(.montserratSemiBold(size: 11))
                .tracking(0.8)
                .foregroundStyle(Color.accent)
                .padding(.horizontal, 20)
                .padding(.top, 18)

            EditorSurface(intervals: intervals, selectedIndex: 0)
        }
        .frame(width: 402)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }
}

/// The editor's own stack, at device width, with no ScrollView or sheet chrome.
private struct EditorSurface: View {
    let intervals: [RoutineInterval]
    let selectedIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoutineEditorStatsRow(
                stats: RoutineEditorStats(intervals: intervals),
                liveKeys: []
            )

            RoutineTimelineEditor(
                intervals: intervals,
                selectedIntervalId: selectedIndex.map { intervals[$0].id },
                onSelect: { _ in },
                onSetLevel: { _, _ in },
                onSetDuration: { _, _ in },
                onAdjustLevel: { _, _ in },
                onAdjustDuration: { _, _ in },
                onCycleStepType: { _ in },
                onDelete: { _ in },
                onMove: { _, _ in },
                onInteractingChange: { _ in }
            )

            if let selectedIndex {
                // `RoutineStepTypeControl` is these two views inside a `Menu`, and a `Menu`
                // renders blank through `ImageRenderer`. The Menu contributes no pixels of
                // its own, so composing its label directly draws the same row.
                HStack(spacing: 10) {
                    RoutineStepTypeRowLabel(
                        stepType: RoutineStepTypeOption.from(modifiers: intervals[selectedIndex].modifiers)
                    )

                    RoutineIntervalDeleteButton(onDelete: {})
                }
            }

            RoutineAddIntervalLabel()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(width: 402)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }
}
