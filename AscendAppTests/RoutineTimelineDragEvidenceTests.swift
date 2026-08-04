import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Filmstrips of the three authoring gestures, rendered frame by frame from the real
/// `RoutineTimelineEditor` while the real `RoutineEditorViewModel` is driven through the same
/// arithmetic the editor's own drag handler uses - `RoutineTimelineLayout.pointsPerLevel`,
/// `pointsPerDurationStep` and `reorderDestinationIndex`. Only the SwiftUI gesture plumbing is
/// stood in for; the geometry, the authoring and the drawing are the shipping ones.
///
/// The static snapshots next door show the surface at rest. A timeline editor is its gestures,
/// so these show the surface moving under a finger.
@MainActor
struct RoutineTimelineDragEvidenceTests {
    /// The routine the design board is drawn with: 3:00, 4:00, 4:00 backward, 3:00, 4:00.
    private static let boardLevels: [(duration: TimeInterval, level: Int, step: RoutineStepTypeOption)] = [
        (180, 16, .standard),
        (240, 7, .standard),
        (240, 6, .backward),
        (180, 20, .standard),
        (240, 4, .standard)
    ]

    /// The plot height the editor actually ships with, so a point of travel here is a point of
    /// travel on the device.
    private static let plotHeight: CGFloat = 210

    /// 402pt of device, less the screen's 20pt gutters and the timeline card's own 14pt inset.
    private static let plotWidth: CGFloat = 402 - 40 - 28

    @Test
    func aVerticalDragWritesOneLevelPerStep() throws {
        let viewModel = try makeViewModel()
        let id = try #require(viewModel.intervals.dropFirst().first?.id)
        viewModel.select(intervalWithId: id)

        let startLevel = viewModel.intervals[1].resolvedLevel
        let pointsPerLevel = RoutineTimelineLayout.pointsPerLevel(plotHeight: Self.plotHeight)
        var frames: [Frame] = []

        // A finger travelling up the plot, sampled at the moments it crosses a level line.
        for stepsUp in [0, 3, 6, 9, 13] {
            let translationHeight = -pointsPerLevel * CGFloat(stepsUp)

            // Verbatim from `RoutineTimelineEditor.updateAdjust`, vertical axis.
            let level = SPMMappingService.clampedLevel(
                startLevel + Int((-translationHeight / pointsPerLevel).rounded())
            )
            viewModel.setLevel(level, forIntervalWithId: id)

            let drawnLevel = viewModel.intervals[1].resolvedLevel
            frames.append(
                Frame(
                    caption: "finger up \(Int((-translationHeight).rounded()))pt   ->   interval 2 is level \(drawnLevel)",
                    intervals: viewModel.intervals,
                    selectedId: id
                )
            )
        }

        // The gesture wrote thirteen levels and nothing else moved.
        #expect(viewModel.intervals[1].resolvedLevel == startLevel + 13)
        #expect(viewModel.intervals.map(\.duration) == Self.boardLevels.map(\.duration))

        try renderFilmstrip(
            named: "routine-builder-drag-level",
            title: "Vertical drag = 1 level",
            frames: frames
        )
    }

    @Test
    func aHorizontalDragWritesThirtySecondsPerStep() throws {
        let viewModel = try makeViewModel()
        let id = try #require(viewModel.intervals.dropFirst().first?.id)
        viewModel.select(intervalWithId: id)

        let startDuration = viewModel.intervals[1].duration

        // Measured once, when the finger lands - exactly as `beginAdjust` does, so the mapping
        // cannot drift under the drag it is driving.
        let contentWidth = Self.plotWidth
            - RoutineTimelineLayout.blockSpacing * CGFloat(viewModel.intervals.count - 1)
        let pointsPerStep = RoutineTimelineLayout.pointsPerDurationStep(
            contentWidth: contentWidth,
            totalDuration: viewModel.intervals.reduce(0) { $0 + $1.duration }
        )
        var frames: [Frame] = []

        for stepsRight in [0, 4, 8, 12] {
            let translationWidth = pointsPerStep * CGFloat(stepsRight)

            // Verbatim from `RoutineTimelineEditor.updateAdjust`, horizontal axis.
            let steps = Int((translationWidth / pointsPerStep).rounded())
            let duration = RoutineIntervalScale.snappedDuration(
                startDuration + Double(steps) * RoutineIntervalScale.durationStep
            )
            viewModel.setDuration(duration, forIntervalWithId: id)

            let drawnClock = viewModel.intervals[1].durationClockLabel
            frames.append(
                Frame(
                    caption: "finger right \(Int(translationWidth.rounded()))pt   ->   interval 2 is \(drawnClock)",
                    intervals: viewModel.intervals,
                    selectedId: id
                )
            )
        }

        // Twelve steps of travel bought exactly twelve 30-second steps, and no level moved.
        #expect(viewModel.intervals[1].duration == startDuration + 12 * 30)
        #expect(viewModel.intervals.map(\.resolvedLevel) == Self.boardLevels.map(\.level))

        try renderFilmstrip(
            named: "routine-builder-drag-duration",
            title: "Horizontal drag = 30 seconds",
            frames: frames
        )
    }

    @Test
    func aHeldBlockDropsWhereTheFingerLeftIt() throws {
        let viewModel = try makeViewModel()
        let id = try #require(viewModel.intervals.dropFirst(3).first?.id)
        viewModel.select(intervalWithId: id)

        let widths = RoutineTimelineLayout.blockWidths(
            durations: viewModel.intervals.map(\.duration),
            availableWidth: Self.plotWidth
        )
        let sourceIndex = 3
        let originX = RoutineTimelineLayout.blockOriginX(at: sourceIndex, widths: widths)
        let width = widths[sourceIndex]

        var frames: [Frame] = [
            Frame(
                caption: "held: the level 20 block is 4th of 5",
                intervals: viewModel.intervals,
                selectedId: id
            )
        ]

        // Carried left across the two blocks in front of it - which are wider than it is, so
        // the travel is their width, not its own - then dropped.
        let translationX = -(widths[1] + widths[2] + RoutineTimelineLayout.blockSpacing * 2)
        let destination = RoutineTimelineLayout.reorderDestinationIndex(
            draggedIndex: sourceIndex,
            draggedCenterX: originX + width / 2 + translationX,
            widths: widths
        )
        viewModel.moveInterval(fromIndex: sourceIndex, toIndex: destination)

        frames.append(
            Frame(
                caption: "dropped: it is 2nd of 5, and order restamps 0-4",
                intervals: viewModel.intervals,
                selectedId: id
            )
        )

        #expect(destination == 1)
        #expect(viewModel.intervals.map(\.resolvedLevel) == [16, 20, 7, 6, 4])
        #expect(viewModel.intervals.map(\.order) == [0, 1, 2, 3, 4])

        try renderFilmstrip(
            named: "routine-builder-reorder",
            title: "Long press, carry, drop",
            frames: frames
        )
    }

    /// Commit 1's defect, drawn: the draft ghost belongs at its own `order`. Appending it drew
    /// the interval being edited as the last bar, so editing interval 2 of 5 rendered it fifth.
    @Test
    func theGhostDrawsInThePlaceOfTheIntervalBeingEdited() throws {
        let saved = Self.boardLevels.enumerated().map { index, spec in
            RoutineInterval(
                duration: spec.duration,
                intensityValue: spec.level,
                modifiers: spec.step.modifiers,
                order: index
            )
        }
        let ghost = RoutineInterval(duration: 240, intensityValue: 24, order: 1)
        let segments = RoutineIntensityChartSegment.segments(intervals: saved, ghostInterval: ghost)

        #expect(segments.map(\.isGhost) == [false, true, false, false, false, false])

        try renderEvidence(
            named: "routine-builder-ghost-placement",
            content: VStack(alignment: .leading, spacing: 14) {
                Caption("Editing interval 2 of 5: the dashed draft draws 2nd, not last")

                RoutineIntensityBarChart(
                    intervals: saved,
                    height: 90,
                    widthMode: .proportionalToDuration,
                    ghostInterval: ghost
                )
            }
            .padding(20)
            .frame(width: 402)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        )
    }

    // MARK: - Rendering

    private struct Frame {
        let caption: String
        let intervals: [RoutineInterval]
        let selectedId: UUID?
    }

    private func renderFilmstrip(named name: String, title: String, frames: [Frame]) throws {
        try renderEvidence(
            named: name,
            content: VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(.white)

                ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                    VStack(alignment: .leading, spacing: 8) {
                        Caption(frame.caption)

                        RoutineTimelineEditor(
                            intervals: frame.intervals,
                            selectedIntervalId: frame.selectedId,
                            plotHeight: Self.plotHeight,
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
                    }
                }
            }
            .padding(20)
            .frame(width: 402)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        )
    }

    /// Annotation, deliberately not a product font, so nobody reads it as shipped copy.
    private struct Caption: View {
        let text: String

        init(_ text: String) {
            self.text = text
        }

        var body: some View {
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.accent)
        }
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
        #expect(png.count > 5_000)
    }

    // MARK: - Fixtures

    private func makeViewModel() throws -> RoutineEditorViewModel {
        let viewModel = RoutineEditorViewModel()
        viewModel.configure(modelContext: try makeModelContext())

        for spec in Self.boardLevels {
            viewModel.addInterval()
            guard let id = viewModel.intervals.last?.id else { continue }
            viewModel.setLevel(spec.level, forIntervalWithId: id)
            viewModel.setDuration(spec.duration, forIntervalWithId: id)
            viewModel.setStepType(spec.step, forIntervalWithId: id)
        }

        return viewModel
    }

    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Routine.self,
            RoutineFolder.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }
}
