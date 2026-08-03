import Foundation
import Testing
@testable import AscendApp

struct RoutineIntensityChartSegmentTests {
    /// The editor drops the interval being edited out of the list and hands the live draft
    /// back as a ghost carrying that interval's `order`.
    private func editorPreview(
        editingOrder: Int,
        draftLevel: Int = 14
    ) -> (intervals: [RoutineInterval], ghost: RoutineInterval) {
        let saved = makeIntervals(levels: [4, 7, 11, 16, 20])
        let remaining = saved.filter { $0.order != editingOrder }
        let ghost = RoutineInterval(
            duration: 120,
            intensityValue: draftLevel,
            order: editingOrder
        )
        return (remaining, ghost)
    }

    private func makeIntervals(levels: [Int]) -> [RoutineInterval] {
        levels.enumerated().map { index, level in
            RoutineInterval(duration: 120, intensityValue: level, order: index)
        }
    }

    @Test
    func editingTheSecondOfFiveIntervalsDrawsTheDraftSecond() {
        let preview = editorPreview(editingOrder: 1)

        let segments = RoutineIntensityChartSegment.segments(
            intervals: preview.intervals,
            ghostInterval: preview.ghost
        )

        #expect(segments.count == 5)
        #expect(segments.map(\.isGhost) == [false, true, false, false, false])
        #expect(segments.map(\.interval.intensityValue) == [4, 14, 11, 16, 20])
    }

    @Test
    func editingTheFirstIntervalDrawsTheDraftFirst() {
        let preview = editorPreview(editingOrder: 0)

        let segments = RoutineIntensityChartSegment.segments(
            intervals: preview.intervals,
            ghostInterval: preview.ghost
        )

        #expect(segments.first?.isGhost == true)
        #expect(segments.map(\.interval.intensityValue) == [14, 7, 11, 16, 20])
    }

    @Test
    func editingTheLastIntervalDrawsTheDraftLast() {
        let preview = editorPreview(editingOrder: 4)

        let segments = RoutineIntensityChartSegment.segments(
            intervals: preview.intervals,
            ghostInterval: preview.ghost
        )

        #expect(segments.last?.isGhost == true)
        #expect(segments.map(\.interval.intensityValue) == [4, 7, 11, 16, 14])
    }

    @Test
    func addingAnIntervalAppendsTheDraftAfterEverythingSaved() {
        let saved = makeIntervals(levels: [4, 7, 11])
        let draft = RoutineInterval(duration: 120, intensityValue: 22, order: saved.count)

        let segments = RoutineIntensityChartSegment.segments(
            intervals: saved,
            ghostInterval: draft
        )

        #expect(segments.map(\.isGhost) == [false, false, false, true])
        #expect(segments.map(\.interval.intensityValue) == [4, 7, 11, 22])
    }

    @Test
    func aGhostOrderPastTheEndClampsInsteadOfTrapping() {
        let saved = makeIntervals(levels: [4, 7])
        let draft = RoutineInterval(duration: 120, intensityValue: 9, order: 97)

        let segments = RoutineIntensityChartSegment.segments(
            intervals: saved,
            ghostInterval: draft
        )

        #expect(segments.count == 3)
        #expect(segments.last?.isGhost == true)
    }

    @Test
    func aNegativeGhostOrderClampsToTheFrontInsteadOfTrapping() {
        let saved = makeIntervals(levels: [4, 7])
        let draft = RoutineInterval(duration: 120, intensityValue: 9, order: -3)

        let segments = RoutineIntensityChartSegment.segments(
            intervals: saved,
            ghostInterval: draft
        )

        #expect(segments.count == 3)
        #expect(segments.first?.isGhost == true)
    }

    @Test
    func withoutAGhostTheSavedIntervalsAreDrawnUntouched() {
        let saved = makeIntervals(levels: [4, 7, 11])

        let segments = RoutineIntensityChartSegment.segments(
            intervals: saved,
            ghostInterval: nil
        )

        #expect(segments.allSatisfy { !$0.isGhost })
        #expect(segments.map(\.interval.id) == saved.map(\.id))
    }
}
