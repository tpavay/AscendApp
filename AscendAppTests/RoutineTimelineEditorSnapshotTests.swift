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
                    mark: .timeline,
                    targetRect: CGRect(x: 20, y: 78, width: 362, height: 262),
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
