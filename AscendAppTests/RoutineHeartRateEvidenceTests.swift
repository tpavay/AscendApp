import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Product-level evidence for issue #241: a routine session driven by a
/// producing chest strap saves heart rate, and a routine without a strap saves
/// clean. Both workouts are built by the real `ActiveRoutineViewModel` save
/// path, persisted to SwiftData, re-fetched from the store, and then rendered
/// through the exact surfaces `WorkoutDetailView` shows for each case
/// (`HeartRateChartView` when data exists, `WorkoutHeartRateRecoveryCard` when
/// it does not) so a reviewer can see what the climber sees.
@MainActor
struct RoutineHeartRateEvidenceTests {
    @Test("Routine heart-rate capture evidence", .bug(id: 241))
    func rendersPersistedRoutineHeartRate() async throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let beats = [112, 118, 126, 133, 141, 148, 154, 159, 162, 158, 151, 144]

        let strapHarness = try makeHarness(startedAt: start, strapBeats: beats)
        let strapWorkout = try await drive(harness: strapHarness, start: start, tickCount: beats.count)

        let bareHarness = try makeHarness(startedAt: start, strapBeats: [])
        let bareWorkout = try await drive(harness: bareHarness, start: start, tickCount: beats.count)

        // Re-fetch from the store so the rendered numbers come from persisted state.
        let persistedStrap = try #require(
            try strapHarness.modelContext.fetch(FetchDescriptor<Workout>()).first
        )
        let persistedBare = try #require(
            try bareHarness.modelContext.fetch(FetchDescriptor<Workout>()).first
        )
        #expect(persistedStrap.id == strapWorkout.id)
        #expect(persistedBare.id == bareWorkout.id)

        // The first tick only establishes the session's tick baseline
        // (ActiveRoutineViewModel.updateActiveSession L621-624), so sampling
        // starts with the second reading.
        let sampledBeats = Array(beats.dropFirst())
        #expect(persistedStrap.avgHeartRate == sampledBeats.reduce(0, +) / sampledBeats.count)
        #expect(persistedStrap.maxHeartRate == sampledBeats.max())
        #expect(persistedStrap.heartRateTimeSeries.map(\.heartRate) == sampledBeats)
        #expect(persistedBare.avgHeartRate == nil)
        #expect(persistedBare.maxHeartRate == nil)
        #expect(persistedBare.heartRateData == nil)

        let renderer = ImageRenderer(
            content: RoutineHeartRateProof(
                strapWorkout: persistedStrap,
                bareWorkout: persistedBare,
                workoutStartTime: start
            )
        )
        renderer.scale = 3
        let image = try #require(renderer.uiImage, "ImageRenderer produced no image")
        let png = try #require(image.pngData(), "UIImage produced no PNG data")

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory)
            .appending(path: "routine-chest-strap-heart-rate.png")
        try png.write(to: url)

        #expect(png.count > 5_000)
    }

    private struct Harness {
        let viewModel: ActiveRoutineViewModel
        let modelContext: ModelContext
        let recorder: LiveHeartRateRecorder
        let source: ScriptedStrapSource
        let container: ModelContainer
    }

    private func drive(
        harness: Harness,
        start: Date,
        tickCount: Int
    ) async throws -> Workout {
        harness.recorder.prepareForSession()
        harness.viewModel.phase = .active
        for index in 0..<tickCount {
            // One reading a minute across the 12-minute routine so the rendered
            // chart spans the session the way a real strap trace does.
            let now = start.addingTimeInterval(Double(index) * 60)
            harness.source.advance(to: now)
            harness.viewModel.handleTick(at: now)
        }
        return try await harness.viewModel.saveRecordedWorkout(
            modelContext: harness.modelContext,
            reason: .targetReached
        )
    }

    private func makeHarness(startedAt: Date, strapBeats: [Int]) throws -> Harness {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            ActiveHeadphoneWorkoutDraft.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = ModelContext(container)
        let routine = Routine(
            id: UUID(uuidString: "41414141-4141-4141-4141-414141414141")!,
            name: "Pyramid Climb",
            source: .builtin,
            intervals: [RoutineInterval(duration: 60, intensityValue: 8, order: 0)],
            templateId: "pyramid_climb"
        )
        let draft = ActiveHeadphoneWorkoutDraft(
            sessionID: "routine-heart-rate-evidence-\(strapBeats.isEmpty ? "bare" : "strap")",
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
            steps: 1_240,
            durationSeconds: 720,
            sampleCount: 720,
            splitCurve: nil,
            trackingIntegrity: .verified,
            stepCorrections: []
        )
        try modelContext.save()

        let source = ScriptedStrapSource(beats: strapBeats, startedAt: startedAt)
        let recorder = LiveHeartRateRecorder(sources: [source])
        let viewModel = ActiveRoutineViewModel(
            routine: routine,
            heartRateRecorder: recorder,
            recoveredDraft: draft
        )
        return Harness(
            viewModel: viewModel,
            modelContext: modelContext,
            recorder: recorder,
            source: source,
            container: container
        )
    }
}

/// Stands in for a paired chest strap: emits one scripted reading per session
/// tick, or nothing at all when the climber wears no strap.
@MainActor
private final class ScriptedStrapSource: LiveHeartRateSource {
    let sourceKind: LiveHeartRateSourceKind = .chestStrap
    private let beats: [Int]
    private var index = -1
    private var current: HeartRateMeasurement?

    init(beats: [Int], startedAt: Date) {
        self.beats = beats
    }

    var isConnected: Bool { !beats.isEmpty }
    var freshMeasurement: HeartRateMeasurement? { current }

    func advance(to date: Date) {
        index += 1
        guard beats.indices.contains(index) else {
            current = nil
            return
        }
        current = HeartRateMeasurement(
            beatsPerMinute: beats[index],
            sensorContact: .detected,
            receivedAt: date
        )
    }

    func prepareForLiveSession() {}
}

private struct RoutineHeartRateProof: View {
    let strapWorkout: Workout
    let bareWorkout: Workout
    let workoutStartTime: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("ROUTINE COMPLETE · SAVED WORKOUT HEART RATE")
                .font(.montserratBold(size: 18))
                .foregroundStyle(.white)
            Text("Both workouts below were built by ActiveRoutineViewModel.saveRecordedWorkout, persisted to SwiftData, and re-read from the store.")
                .font(.montserratRegular(size: 12))
                .foregroundStyle(.white.opacity(0.7))

            panel(
                title: "Chest strap connected · \(strapWorkout.name)",
                detail: "avgHeartRate \(describe(strapWorkout.avgHeartRate)) · maxHeartRate \(describe(strapWorkout.maxHeartRate)) · \(strapWorkout.heartRateTimeSeries.count) samples"
            ) {
                HeartRateChartView(
                    heartRateData: strapWorkout.heartRateTimeSeries,
                    workoutStartTime: workoutStartTime,
                    workoutDuration: strapWorkout.duration,
                    averageHeartRateBpm: strapWorkout.avgHeartRate,
                    maxHeartRateBpm: strapWorkout.maxHeartRate
                )
            }

            panel(
                title: "No strap · \(bareWorkout.name)",
                detail: "avgHeartRate \(describe(bareWorkout.avgHeartRate)) · maxHeartRate \(describe(bareWorkout.maxHeartRate)) · \(bareWorkout.heartRateTimeSeries.count) samples · saved cleanly"
            ) {
                WorkoutHeartRateRecoveryCard(
                    connectionState: .connected,
                    isFetching: false,
                    hasStoppedAutomaticChecks: false,
                    message: nil,
                    effectiveColorScheme: .dark,
                    onFetch: {}
                )
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(Color.jet)
        .environment(\.colorScheme, .dark)
    }

    private func describe(_ value: Int?) -> String {
        value.map(String.init) ?? "nil"
    }

    @ViewBuilder
    private func panel(
        title: String,
        detail: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.montserratSemiBold(size: 13))
                .foregroundStyle(Color.accentColor)
            Text(detail)
                .font(.montserratRegular(size: 11))
                .foregroundStyle(.white.opacity(0.75))
            content()
        }
    }
}
