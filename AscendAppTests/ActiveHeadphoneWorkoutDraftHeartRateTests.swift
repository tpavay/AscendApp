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
            heartRateBuffer: HeartRateSessionSampleBuffer(restoring: samples)
        )

        let workout = ActiveHeadphoneWorkoutDraftSaver.makeRecoveredWorkout(
            from: draft,
            deviceModel: "Test Device"
        )
        let metadata = try decodeMetadata(from: workout)

        #expect(draft.heartRateSampleCount == samples.count)
        #expect(workout.heartRateTimeSeries == samples)
        #expect(workout.avgHeartRate == 140)
        #expect(workout.maxHeartRate == 148)
        #expect(metadata.heartRateCoverage?.status == .partial)
        #expect(metadata.heartRateCoverage?.sampleCount == samples.count)
    }

    @Test("The incrementally built payload decodes back to the whole series")
    func encodedPayloadDecodesBackToTheWholeSeries() throws {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = (0..<50).map { index in
            HeartRateDataPoint(
                timestamp: startedAt.addingTimeInterval(TimeInterval(index)),
                heartRate: 120 + index
            )
        }
        var buffer = HeartRateSessionSampleBuffer()
        for (index, sample) in samples.enumerated() {
            buffer.record(
                beatsPerMinute: sample.heartRate,
                capturedAt: startedAt.addingTimeInterval(TimeInterval(index)),
                sessionStartedAt: startedAt,
                sessionElapsed: TimeInterval(index)
            )
        }

        let payload = try #require(buffer.encodedPayload)

        #expect(buffer.samples == samples)
        #expect(try JSONDecoder().decode([HeartRateDataPoint].self, from: payload) == samples)
        #expect(HeartRateSessionSampleBuffer().encodedPayload == nil)
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
            heartRateBuffer: HeartRateSessionSampleBuffer(restoring: preInterruptionSamples)
        )

        // The resumed session runs minutes after the interruption, so a view
        // model anchoring samples to wall-clock capture time instead of the
        // draft's start plus the resume-inclusive elapsed clock would land them
        // far past the end of the workout.
        let motionSession = HeadphoneMotionSessionService()
        let viewModel = LiveClimbSessionViewModel(
            justClimbGoal: JustClimbGoal(),
            motionSession: motionSession,
            recoveredDraft: draft
        )
        let resumedAt = startedAt.addingTimeInterval(300)

        #expect(viewModel.heartRateSamplesSnapshot == preInterruptionSamples)

        motionSession.primeDurationForTesting(30)
        viewModel.recordHeartRateSample(measurement(146, at: resumedAt), capturedAt: resumedAt)
        motionSession.primeDurationForTesting(31)
        viewModel.recordHeartRateSample(
            measurement(146, at: resumedAt.addingTimeInterval(1)),
            capturedAt: resumedAt.addingTimeInterval(1)
        )
        motionSession.primeDurationForTesting(32)
        viewModel.recordHeartRateSample(
            measurement(148, at: resumedAt.addingTimeInterval(2)),
            capturedAt: resumedAt.addingTimeInterval(2)
        )

        #expect(viewModel.heartRateSamplesSnapshot.map(\.heartRate) == [142, 144, 146, 148])
        #expect(
            viewModel.heartRateSamplesSnapshot.map { $0.timestamp.timeIntervalSince(startedAt) }
                == [29, 30, 31, 32]
        )
    }

    @Test("A sample recorded without an active draft keeps its capture time")
    func recordingWithoutADraftIsNotMisdated() {
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let motionSession = HeadphoneMotionSessionService()
        let viewModel = LiveClimbSessionViewModel(
            justClimbGoal: JustClimbGoal(),
            motionSession: motionSession
        )
        // No draft means no logical timeline to anchor to, so the elapsed clock
        // must not be projected onto the sample - it would land in the future.
        motionSession.primeDurationForTesting(300)

        viewModel.recordHeartRateSample(
            measurement(150, at: capturedAt),
            capturedAt: capturedAt
        )

        #expect(viewModel.heartRateSamplesSnapshot.map(\.timestamp) == [capturedAt])
    }

    @Test("A draft carrying no heart-rate payload round-trips and saves cleanly")
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
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = makeDraft(startedAt: startedAt)
        // A draft written before the heart-rate payload existed carries neither
        // the blob nor its count - exactly what the additive migration leaves
        // behind for every checkpoint the pre-fix build wrote.
        draft.heartRateData = nil
        draft.heartRateSampleCount = nil

        try store.insert(draft, in: modelContext)
        draft.applyCheckpoint(
            steps: 300,
            durationSeconds: 120,
            sampleCount: 6_000,
            splitCurve: nil,
            trackingIntegrity: .verified,
            stepCorrections: []
        )
        try modelContext.save()

        let loadedDraft = try #require(try store.activeDraft(in: modelContext))

        #expect(loadedDraft.heartRateData == nil)
        #expect(loadedDraft.heartRateSampleCount == nil)
        #expect(loadedDraft.heartRateSamples.isEmpty)
        #expect(loadedDraft.diagnosticDetails["heart_rate_sample_count"] == "0")

        let workout = ActiveHeadphoneWorkoutDraftSaver.makeRecoveredWorkout(
            from: loadedDraft,
            deviceModel: "Test Device"
        )
        let metadata = try decodeMetadata(from: workout)

        #expect(workout.heartRateTimeSeries.isEmpty)
        #expect(workout.avgHeartRate == nil)
        #expect(workout.maxHeartRate == nil)
        #expect(metadata.heartRateCoverage == nil)
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

    private func measurement(_ beatsPerMinute: Int, at receivedAt: Date) -> HeartRateMeasurement {
        HeartRateMeasurement(
            beatsPerMinute: beatsPerMinute,
            sensorContact: .detected,
            receivedAt: receivedAt
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
