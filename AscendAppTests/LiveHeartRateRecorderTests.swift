import Foundation
import SwiftData
import Testing
@testable import AscendApp

@MainActor
struct LiveHeartRateRecorderTests {
    @Test("Chest strap outranks Apple Watch", .bug(id: 241))
    func chestStrapOutranksAppleWatch() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let watch = FakeLiveHeartRateSource(
            sourceKind: .appleWatch,
            measurement: measurement(90, at: now)
        )
        let strap = FakeLiveHeartRateSource(
            sourceKind: .chestStrap,
            measurement: measurement(150, at: now)
        )
        for sources in [[watch, strap], [strap, watch]] {
            let recorder = LiveHeartRateRecorder(sources: sources)
            recorder.recordSample(at: now)

            #expect(recorder.currentSourceKind == .chestStrap)
            #expect(recorder.currentMeasurement?.beatsPerMinute == 150)
            #expect(recorder.workoutSummary.averageHeartRate == 150)
            #expect(recorder.workoutSummary.maximumHeartRate == 150)
            #expect(recorder.workoutSummary.timeSeries?.map(\.heartRate) == [150])
        }
    }

    @Test("Shared recorder is session-type agnostic", .bug(id: 241))
    func sharedRecorderProducesIdenticalSummariesAcrossSessionTypes() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let liveClimbSource = makeProducingSource(at: start)
        let justClimbSource = makeProducingSource(at: start)
        let routineSource = makeProducingSource(at: start)
        let liveClimbRecorder = LiveHeartRateRecorder(sources: [liveClimbSource])
        let justClimbRecorder = LiveHeartRateRecorder(sources: [justClimbSource])
        let routineRecorder = LiveHeartRateRecorder(sources: [routineSource])
        let liveClimb = LiveClimbSessionViewModel(
            climb: .preview,
            heartRateRecorder: liveClimbRecorder
        )
        let justClimb = LiveClimbSessionViewModel(
            justClimbGoal: JustClimbGoal(),
            heartRateRecorder: justClimbRecorder
        )
        let routine = ActiveRoutineViewModel(
            routine: makeRoutine(),
            heartRateRecorder: routineRecorder
        )

        [liveClimbRecorder, justClimbRecorder, routineRecorder].forEach {
            $0.prepareForSession()
        }
        liveClimb.recordHeartRateSampleForSessionTick(at: start)
        justClimb.recordHeartRateSampleForSessionTick(at: start)
        routine.recordHeartRateSampleForSessionTick(at: start)
        liveClimbSource.measurement = measurement(160, at: start.addingTimeInterval(1))
        justClimbSource.measurement = measurement(160, at: start.addingTimeInterval(1))
        routineSource.measurement = measurement(160, at: start.addingTimeInterval(1))
        liveClimb.recordHeartRateSampleForSessionTick(at: start.addingTimeInterval(1))
        justClimb.recordHeartRateSampleForSessionTick(at: start.addingTimeInterval(1))
        routine.recordHeartRateSampleForSessionTick(at: start.addingTimeInterval(1))

        let expected = liveClimb.heartRateWorkoutSummary
        #expect(justClimb.heartRateWorkoutSummary == expected)
        #expect(routine.heartRateWorkoutSummary == expected)
        #expect(expected.averageHeartRate == 140)
        #expect(expected.maximumHeartRate == 160)
        #expect(expected.timeSeries?.count == 2)
    }

    @Test("Routine save persists producing strap samples", .bug(id: 241))
    func routineSavePersistsProducingStrapSamples() async throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let source = FakeLiveHeartRateSource(
            sourceKind: .chestStrap,
            measurement: measurement(120, at: start)
        )
        let harness = try makeRoutineHarness(source: source, startedAt: start)

        harness.recorder.prepareForSession()
        harness.viewModel.phase = .active
        harness.viewModel.handleTick(at: start)
        harness.viewModel.handleTick(at: start.addingTimeInterval(1))
        source.measurement = measurement(160, at: start.addingTimeInterval(2))
        harness.viewModel.handleTick(at: start.addingTimeInterval(2))

        let workout = try await harness.viewModel.saveRecordedWorkout(
            modelContext: harness.modelContext,
            reason: .targetReached
        )

        #expect(source.prepareCallCount == 1)
        #expect(workout.avgHeartRate == 140)
        #expect(workout.maxHeartRate == 160)
        #expect(workout.heartRateTimeSeries.map(\.heartRate) == [120, 160])
    }

    @Test("Routine save without a live source keeps heart rate empty", .bug(id: 241))
    func routineSaveWithoutStrapPersistsNoHeartRate() async throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let source = FakeLiveHeartRateSource(sourceKind: .chestStrap, measurement: nil)
        let harness = try makeRoutineHarness(source: source, startedAt: start)

        harness.recorder.prepareForSession()
        harness.viewModel.phase = .active
        harness.viewModel.handleTick(at: start)
        harness.viewModel.handleTick(at: start.addingTimeInterval(1))

        let workout = try await harness.viewModel.saveRecordedWorkout(
            modelContext: harness.modelContext,
            reason: .targetReached
        )

        #expect(source.prepareCallCount == 1)
        #expect(workout.avgHeartRate == nil)
        #expect(workout.maxHeartRate == nil)
        #expect(workout.heartRateData == nil)
        #expect(workout.heartRateTimeSeries.isEmpty)
    }

    @Test("Routine start prepares the shared recorder without delaying countdown", .bug(id: 241))
    func routineStartPreparesSharedRecorder() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let source = FakeLiveHeartRateSource(sourceKind: .chestStrap, measurement: nil)
        let harness = try makeRoutineHarness(source: source, startedAt: start)

        harness.viewModel.startSession(modelContext: harness.modelContext)
        harness.viewModel.stopTimer()

        #expect(source.prepareCallCount == 1)
        #expect(harness.viewModel.phase == .countdown)
    }

    private func makeRoutineHarness(
        source: FakeLiveHeartRateSource,
        startedAt: Date
    ) throws -> (
        viewModel: ActiveRoutineViewModel,
        modelContext: ModelContext,
        recorder: LiveHeartRateRecorder
    ) {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            ActiveHeadphoneWorkoutDraft.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = ModelContext(container)
        let routine = makeRoutine()
        let draft = ActiveHeadphoneWorkoutDraft(
            sessionID: "routine-heart-rate-test",
            kind: .routine,
            startedAt: startedAt,
            title: routine.name,
            subtitle: "",
            workoutName: routine.name,
            targetStepCount: 900,
            targetDurationSeconds: routine.totalDuration,
            routineId: routine.id,
            routineSource: routine.source,
            routineTemplateId: routine.templateId
        )
        modelContext.insert(draft)
        draft.applyCheckpoint(
            steps: 1_200,
            durationSeconds: 10,
            sampleCount: 60,
            splitCurve: nil,
            trackingIntegrity: .verified,
            stepCorrections: []
        )
        try modelContext.save()

        let recorder = LiveHeartRateRecorder(sources: [source])
        let viewModel = ActiveRoutineViewModel(
            routine: routine,
            heartRateRecorder: recorder,
            recoveredDraft: draft
        )
        return (viewModel, modelContext, recorder)
    }

    private func measurement(_ beatsPerMinute: Int, at date: Date) -> HeartRateMeasurement {
        HeartRateMeasurement(
            beatsPerMinute: beatsPerMinute,
            sensorContact: .detected,
            receivedAt: date
        )
    }

    private func makeProducingSource(at date: Date) -> FakeLiveHeartRateSource {
        FakeLiveHeartRateSource(
            sourceKind: .chestStrap,
            measurement: measurement(120, at: date)
        )
    }

    private func makeRoutine() -> Routine {
        Routine(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            name: "Pyramid Climb",
            source: .builtin,
            intervals: [RoutineInterval(duration: 60, intensityValue: 8, order: 0)],
            templateId: "pyramid_climb"
        )
    }
}

@MainActor
private final class FakeLiveHeartRateSource: LiveHeartRateSource {
    let sourceKind: LiveHeartRateSourceKind
    var measurement: HeartRateMeasurement?
    var isConnected = true
    private(set) var prepareCallCount = 0

    init(
        sourceKind: LiveHeartRateSourceKind,
        measurement: HeartRateMeasurement?
    ) {
        self.sourceKind = sourceKind
        self.measurement = measurement
    }

    var freshMeasurement: HeartRateMeasurement? {
        measurement
    }

    func prepareForLiveSession() {
        prepareCallCount += 1
    }
}
