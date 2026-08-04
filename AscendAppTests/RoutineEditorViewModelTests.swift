import Foundation
import SwiftData
import Testing
@testable import AscendApp

@MainActor
struct RoutineEditorViewModelTests {
    // MARK: - Adding

    /// Tapping + lands a block ready to drag. There is no creator sheet and no step-type
    /// prompt, because four intervals out of five are Standard anyway.
    @Test
    func addingAnIntervalLandsAStandardBlockAtLevelOneAndSelectsIt() throws {
        let viewModel = try makeViewModel()

        viewModel.addInterval()

        let interval = try #require(viewModel.intervals.first)
        #expect(viewModel.intervals.count == 1)
        #expect(interval.resolvedLevel == 1)
        #expect(interval.duration == 120)
        #expect(RoutineStepTypeOption.from(modifiers: interval.modifiers) == .standard)
        #expect(viewModel.selectedIntervalId == interval.id)
        #expect(viewModel.selectedStepType == .standard)
    }

    @Test
    func everyAddedIntervalTakesTheNextOrder() throws {
        let viewModel = try makeViewModel()

        viewModel.addInterval()
        viewModel.addInterval()
        viewModel.addInterval()

        #expect(viewModel.intervals.map(\.order) == [0, 1, 2])
    }

    // MARK: - Dragging

    @Test
    func draggingUpWritesTheLevelAndStopsAtTheTopOfTheScale() throws {
        let viewModel = try makeViewModel(levels: [4])
        let id = try #require(viewModel.intervals.first?.id)

        viewModel.setLevel(17, forIntervalWithId: id)
        #expect(viewModel.intervals[0].resolvedLevel == 17)

        viewModel.setLevel(88, forIntervalWithId: id)
        #expect(viewModel.intervals[0].resolvedLevel == 25)

        viewModel.setLevel(-4, forIntervalWithId: id)
        #expect(viewModel.intervals[0].resolvedLevel == 1)
    }

    @Test
    func theAdjustableActionMovesTheLevelOneStepAtATime() throws {
        let viewModel = try makeViewModel(levels: [7])
        let id = try #require(viewModel.intervals.first?.id)

        viewModel.adjustLevel(by: 1, forIntervalWithId: id)
        #expect(viewModel.intervals[0].resolvedLevel == 8)

        viewModel.adjustLevel(by: -1, forIntervalWithId: id)
        #expect(viewModel.intervals[0].resolvedLevel == 7)
    }

    @Test
    func draggingSidewaysOnlyEverWritesDurationsTheModelAlreadyStores() throws {
        let viewModel = try makeViewModel(levels: [12])
        let id = try #require(viewModel.intervals.first?.id)

        viewModel.setDuration(146, forIntervalWithId: id)
        #expect(viewModel.intervals[0].duration == 150)

        viewModel.setDuration(4, forIntervalWithId: id)
        #expect(viewModel.intervals[0].duration == 30)

        viewModel.setDuration(9_999, forIntervalWithId: id)
        #expect(viewModel.intervals[0].duration == 1_800)
    }

    @Test
    func theRotorTimeActionsMoveInThirtySecondSteps() throws {
        let viewModel = try makeViewModel(levels: [12])
        let id = try #require(viewModel.intervals.first?.id)

        viewModel.adjustDuration(bySteps: 1, forIntervalWithId: id)
        #expect(viewModel.intervals[0].duration == 150)

        viewModel.adjustDuration(bySteps: -2, forIntervalWithId: id)
        #expect(viewModel.intervals[0].duration == 90)
    }

    // MARK: - Step type

    @Test
    func theStepControlWritesToWhicheverBlockIsSelected() throws {
        let viewModel = try makeViewModel(levels: [4, 7, 11])
        let id = viewModel.intervals[1].id
        viewModel.select(intervalWithId: id)

        viewModel.setStepType(.backward, forIntervalWithId: id)

        #expect(viewModel.selectedStepType == .backward)
        #expect(RoutineStepTypeOption.from(modifiers: viewModel.intervals[0].modifiers) == .standard)
        #expect(RoutineStepTypeOption.from(modifiers: viewModel.intervals[2].modifiers) == .standard)
    }

    @Test
    func theRotorStepActionWalksTheFiveOptionsAndWrapsBackToStandard() throws {
        let viewModel = try makeViewModel(levels: [4])
        let id = try #require(viewModel.intervals.first?.id)

        var seen: [RoutineStepTypeOption] = []
        for _ in RoutineStepTypeOption.allCases {
            viewModel.cycleStepType(forIntervalWithId: id)
            seen.append(RoutineStepTypeOption.from(modifiers: viewModel.intervals[0].modifiers))
        }

        #expect(Set(seen) == Set(RoutineStepTypeOption.allCases))
        #expect(seen.last == .standard)
    }

    // MARK: - Reordering

    @Test
    func aBlockDroppedEarlierTakesItsNewOrderAndSoDoEveryoneElse() throws {
        let viewModel = try makeViewModel(levels: [4, 7, 11, 16, 20])

        viewModel.moveInterval(fromIndex: 3, toIndex: 1)

        #expect(viewModel.intervals.map(\.resolvedLevel) == [4, 16, 7, 11, 20])
        #expect(viewModel.intervals.map(\.order) == [0, 1, 2, 3, 4])
    }

    @Test
    func aBlockDroppedLaterTakesItsNewOrder() throws {
        let viewModel = try makeViewModel(levels: [4, 7, 11, 16, 20])

        viewModel.moveInterval(fromIndex: 0, toIndex: 3)

        #expect(viewModel.intervals.map(\.resolvedLevel) == [7, 11, 16, 4, 20])
        #expect(viewModel.intervals.map(\.order) == [0, 1, 2, 3, 4])
    }

    @Test
    func aBlockDroppedWhereItStartedChangesNothing() throws {
        let viewModel = try makeViewModel(levels: [4, 7, 11])

        viewModel.moveInterval(fromIndex: 1, toIndex: 1)

        #expect(viewModel.intervals.map(\.resolvedLevel) == [4, 7, 11])
    }

    @Test
    func theRotorMoveActionsCannotWalkAnIntervalOffEitherEnd() throws {
        let viewModel = try makeViewModel(levels: [4, 7, 11])
        viewModel.select(intervalWithId: viewModel.intervals[0].id)

        viewModel.moveSelectedInterval(by: -1)
        #expect(viewModel.intervals.map(\.resolvedLevel) == [4, 7, 11])

        viewModel.select(intervalWithId: viewModel.intervals[2].id)
        viewModel.moveSelectedInterval(by: 1)
        #expect(viewModel.intervals.map(\.resolvedLevel) == [4, 7, 11])
    }

    @Test
    func movingABlockKeepsItSelected() throws {
        let viewModel = try makeViewModel(levels: [4, 7, 11, 16])
        let id = viewModel.intervals[3].id
        viewModel.select(intervalWithId: id)

        viewModel.moveInterval(fromIndex: 3, toIndex: 0)

        #expect(viewModel.selectedIntervalId == id)
        #expect(viewModel.intervals.first?.id == id)
    }

    // MARK: - Deleting

    @Test
    func deletingABlockRenumbersTheRestAndSelectsWhateverTookItsPlace() throws {
        let viewModel = try makeViewModel(levels: [4, 7, 11, 16])
        let deletedId = viewModel.intervals[1].id

        viewModel.deleteInterval(withId: deletedId)

        #expect(viewModel.intervals.map(\.resolvedLevel) == [4, 11, 16])
        #expect(viewModel.intervals.map(\.order) == [0, 1, 2])
        #expect(viewModel.selectedIntervalId == viewModel.intervals[1].id)
    }

    @Test
    func deletingTheLastBlockSelectsTheOneBeforeIt() throws {
        let viewModel = try makeViewModel(levels: [4, 7, 11])

        viewModel.deleteInterval(withId: viewModel.intervals[2].id)

        #expect(viewModel.selectedIntervalId == viewModel.intervals[1].id)
    }

    @Test
    func deletingTheOnlyBlockLeavesNothingSelectedSoTheStepControlGoesAway() throws {
        let viewModel = try makeViewModel(levels: [4])

        viewModel.deleteInterval(withId: viewModel.intervals[0].id)

        #expect(viewModel.intervals.isEmpty)
        #expect(viewModel.selectedIntervalId == nil)
        #expect(viewModel.selectedInterval == nil)
        #expect(viewModel.stats.isEmpty)
    }

    // MARK: - Saving

    @Test
    func aRoutineCannotBeSavedWithoutANameOrWithoutIntervals() throws {
        let viewModel = try makeViewModel()

        #expect(!viewModel.canSave)

        viewModel.name = "Tempo Switch"
        #expect(!viewModel.canSave)

        viewModel.addInterval()
        #expect(viewModel.canSave)

        viewModel.name = "   "
        #expect(!viewModel.canSave)
    }

    /// Save stays explicit: `RoutineService.kickBackup()` fires a Firestore upload pass per
    /// write, so nothing the drag touches may reach the store on its own.
    @Test
    func draggingNeverWritesToTheStore() throws {
        let modelContext = try makeModelContext()
        let viewModel = RoutineEditorViewModel()
        viewModel.configure(modelContext: modelContext)

        viewModel.name = "Tempo Switch"
        viewModel.addInterval()

        let id = try #require(viewModel.intervals.first?.id)
        viewModel.setLevel(20, forIntervalWithId: id)
        viewModel.setDuration(600, forIntervalWithId: id)
        viewModel.setStepType(.backward, forIntervalWithId: id)
        viewModel.moveInterval(fromIndex: 0, toIndex: 0)

        #expect(try modelContext.fetch(FetchDescriptor<Routine>()).isEmpty)
    }

    @Test
    func savingPersistsTheIntervalsInTheOrderTheTimelineShows() throws {
        let modelContext = try makeModelContext()
        let viewModel = RoutineEditorViewModel()
        viewModel.configure(modelContext: modelContext)

        viewModel.name = "Tempo Switch"
        viewModel.addInterval()
        viewModel.addInterval()
        viewModel.setLevel(20, forIntervalWithId: viewModel.intervals[0].id)
        viewModel.moveInterval(fromIndex: 0, toIndex: 1)

        let saved = try viewModel.save()

        #expect(saved.intervals.map(\.order) == [0, 1])
        #expect(saved.intervals.map(\.resolvedLevel) == [1, 20])
    }

    @Test
    func openingAnExistingRoutineSelectsItsFirstIntervalSoTheStepControlHasAValue() throws {
        let modelContext = try makeModelContext()
        let routine = Routine(
            name: "Tempo Switch",
            intervals: [
                RoutineInterval(duration: 180, intensityValue: 16, order: 0),
                RoutineInterval(duration: 240, intensityValue: 7, order: 1)
            ]
        )

        let viewModel = RoutineEditorViewModel()
        viewModel.configure(modelContext: modelContext, routine: routine)

        #expect(viewModel.selectedIntervalId == viewModel.intervals.first?.id)
        #expect(viewModel.stats.totalMinutes == 7)
        #expect(viewModel.navigationTitle == "Edit Routine")
    }

    // MARK: - Helpers

    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Routine.self,
            RoutineFolder.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeViewModel(levels: [Int] = []) throws -> RoutineEditorViewModel {
        let viewModel = RoutineEditorViewModel()
        viewModel.configure(modelContext: try makeModelContext())

        for level in levels {
            viewModel.addInterval()
            if let id = viewModel.intervals.last?.id {
                viewModel.setLevel(level, forIntervalWithId: id)
            }
        }

        return viewModel
    }
}
