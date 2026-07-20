import Foundation
import SwiftData
import Testing
@testable import AscendApp

@MainActor
struct ActiveHeadphoneWorkoutDraftHeartRateTests {
    @Test("Recovery save preserves checkpointed chest-strap samples")
    func recoverySavePreservesCheckpointedHeartRate() throws {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = [
            HeartRateDataPoint(timestamp: startedAt.addingTimeInterval(60), heartRate: 132),
            HeartRateDataPoint(timestamp: startedAt.addingTimeInterval(120), heartRate: 148)
        ]
        let draft = makeDraft(startedAt: startedAt)
        draft.applyCheckpoint(
            steps: 450,
            durationSeconds: 180,
            sampleCount: 9_000,
            splitCurve: nil,
            trackingIntegrity: .verified,
            stepCorrections: [],
            heartRateSamples: samples
        )

        let workout = ActiveHeadphoneWorkoutDraftSaver.makeRecoveredWorkout(
            from: draft,
            deviceModel: "Test Device"
        )
        let metadata = try decodeMetadata(from: workout)

        #expect(workout.heartRateTimeSeries == samples)
        #expect(workout.avgHeartRate == 140)
        #expect(workout.maxHeartRate == 148)
        #expect(metadata.heartRateCoverage?.status == .partial)
        #expect(metadata.heartRateCoverage?.sampleCount == samples.count)
    }

    @Test("Resume appends to the checkpointed series on the workout timeline")
    func resumeProducesOneContinuousHeartRateSeries() {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let preInterruptionSamples = [
            HeartRateDataPoint(timestamp: startedAt.addingTimeInterval(29), heartRate: 142),
            HeartRateDataPoint(timestamp: startedAt.addingTimeInterval(30), heartRate: 144)
        ]
        let draft = makeDraft(startedAt: startedAt)
        draft.applyCheckpoint(
            steps: 200,
            durationSeconds: 30,
            sampleCount: 1_500,
            splitCurve: nil,
            trackingIntegrity: .verified,
            stepCorrections: [],
            heartRateSamples: preInterruptionSamples
        )
        let viewModel = LiveClimbSessionViewModel(
            justClimbGoal: JustClimbGoal(),
            recoveredDraft: draft
        )
        var buffer = HeartRateSessionSampleBuffer(restoring: preInterruptionSamples)
        let resumedAt = startedAt.addingTimeInterval(300)

        buffer.record(
            beatsPerMinute: 146,
            capturedAt: resumedAt,
            sessionStartedAt: startedAt,
            sessionElapsed: 30
        )
        buffer.record(
            beatsPerMinute: 146,
            capturedAt: resumedAt.addingTimeInterval(1),
            sessionStartedAt: startedAt,
            sessionElapsed: 31
        )
        buffer.record(
            beatsPerMinute: 148,
            capturedAt: resumedAt.addingTimeInterval(2),
            sessionStartedAt: startedAt,
            sessionElapsed: 32
        )

        #expect(buffer.samples.map(\.heartRate) == [142, 144, 146, 148])
        #expect(viewModel.heartRateSamplesSnapshot == preInterruptionSamples)
        #expect(
            buffer.samples.map { $0.timestamp.timeIntervalSince(startedAt) } == [29, 30, 31, 32]
        )
    }

    @Test("A legacy draft without heart-rate payload still loads")
    func legacyDraftWithoutHeartRatePayloadLoads() throws {
        let suiteName = "ActiveHeadphoneWorkoutDraftHeartRateTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let container = try ModelContainer(
            for: ActiveHeadphoneWorkoutDraft.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = ModelContext(container)
        let store = ActiveHeadphoneWorkoutDraftStore(userDefaults: userDefaults)
        let draft = makeDraft(startedAt: Date(timeIntervalSince1970: 1_800_000_000))

        try store.insert(draft, in: modelContext)
        let activeDraft = try store.activeDraft(in: modelContext)
        let loadedDraft = try #require(activeDraft)

        #expect(loadedDraft.heartRateData == nil)
        #expect(loadedDraft.heartRateSamples.isEmpty)
    }

    @Test("Coverage marks a trace that spans only part of the session as partial")
    func partialCoverageIsRecordedHonestly() throws {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let coverage = try #require(
            HeartRateTraceCoverage(
                samples: [
                    HeartRateDataPoint(timestamp: startedAt.addingTimeInterval(40), heartRate: 140),
                    HeartRateDataPoint(timestamp: startedAt.addingTimeInterval(41), heartRate: 141)
                ],
                sessionStartedAt: startedAt,
                sessionDuration: 100
            )
        )

        #expect(coverage.status == .partial)
        #expect(coverage.coverageFraction < 0.1)
        #expect(coverage.sessionDurationSeconds == 100)
    }

    private func makeDraft(startedAt: Date) -> ActiveHeadphoneWorkoutDraft {
        ActiveHeadphoneWorkoutDraft(
            sessionID: "heart-rate-recovery",
            kind: .justClimb,
            startedAt: startedAt,
            title: "Just Climb",
            subtitle: "Open session",
            workoutName: "Just Climb",
            targetStepCount: nil,
            targetDurationSeconds: nil
        )
    }

    private func decodeMetadata(from workout: Workout) throws -> HeadphoneMotionWorkoutMetadata {
        let sourceMetadata = try #require(workout.sourceMetadata)
        return try JSONDecoder().decode(
            HeadphoneMotionWorkoutMetadata.self,
            from: Data(sourceMetadata.utf8)
        )
    }
}
