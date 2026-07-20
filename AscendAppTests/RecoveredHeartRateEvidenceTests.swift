import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Reviewer-visible evidence for the recovered/resumed chest-strap heart-rate fix.
///
/// Drives the real production types end to end:
///   record via `LiveClimbSessionViewModel.recordHeartRateSample`
///     -> checkpoint into `ActiveHeadphoneWorkoutDraft`
///     -> app dies -> recover -> `ActiveHeadphoneWorkoutDraftSaver.makeRecoveredWorkout`
///     -> render the resulting `Workout` through the shipping `HeartRateChartView`
///        (the exact component `WorkoutDetailView.heartRateSection` shows).
///
/// Writes a PNG and a JSON dump to `ASCEND_EVIDENCE_DIR` (temp dir otherwise).
@MainActor
struct RecoveredHeartRateEvidenceTests {
    private static let startedAt = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Evidence: recovered and resumed sessions keep the chest-strap trace")
    func renderRecoveredHeartRateEvidence() throws {
        // --- Phase 1: live session with a strap, 90s captured, then killed -----
        let draft = makeDraft()
        let liveSession = HeadphoneMotionSessionService()
        let liveViewModel = LiveClimbSessionViewModel(
            justClimbGoal: JustClimbGoal(),
            motionSession: liveSession,
            recoveredDraft: draft
        )
        for second in 0..<90 {
            liveSession.primeDurationForTesting(TimeInterval(second))
            liveViewModel.recordHeartRateSample(
                HeartRateMeasurement(
                    beatsPerMinute: 118 + Int((Double(second) / 6).rounded()),
                    sensorContact: .detected,
                    receivedAt: Self.startedAt.addingTimeInterval(TimeInterval(second))
                ),
                capturedAt: Self.startedAt.addingTimeInterval(TimeInterval(second))
            )
        }
        draft.applyCheckpoint(
            steps: 1_100,
            durationSeconds: 90,
            sampleCount: 4_500,
            splitCurve: nil,
            trackingIntegrity: .verified,
            stepCorrections: [],
            heartRateBuffer: HeartRateSessionSampleBuffer(restoring: liveViewModel.heartRateSamplesSnapshot)
        )

        // Only what SwiftData persisted survives the crash.
        let persistedDraft = makeDraft()
        persistedDraft.heartRateData = draft.heartRateData
        persistedDraft.heartRateSampleCount = draft.heartRateSampleCount
        persistedDraft.applyCheckpoint(
            steps: draft.steps,
            durationSeconds: draft.durationSeconds,
            sampleCount: draft.sampleCount,
            splitCurve: nil,
            trackingIntegrity: .verified,
            stepCorrections: []
        )

        // --- Path A: user saves straight from the recovery prompt -------------
        let recoveredWorkout = ActiveHeadphoneWorkoutDraftSaver.makeRecoveredWorkout(
            from: persistedDraft,
            deviceModel: "iPhone"
        )

        // --- Path B: user resumes instead, strap keeps streaming --------------
        let resumedSession = HeadphoneMotionSessionService()
        let resumedViewModel = LiveClimbSessionViewModel(
            justClimbGoal: JustClimbGoal(),
            motionSession: resumedSession,
            recoveredDraft: persistedDraft
        )
        // Wall clock is minutes past the interruption; the logical timeline is not.
        let resumeWallClock = Self.startedAt.addingTimeInterval(600)
        for offset in 0..<60 {
            resumedSession.primeDurationForTesting(TimeInterval(90 + offset))
            resumedViewModel.recordHeartRateSample(
                HeartRateMeasurement(
                    beatsPerMinute: 133 + Int((Double(offset) / 4).rounded()),
                    sensorContact: .detected,
                    receivedAt: resumeWallClock.addingTimeInterval(TimeInterval(offset))
                ),
                capturedAt: resumeWallClock.addingTimeInterval(TimeInterval(offset))
            )
        }
        persistedDraft.applyCheckpoint(
            steps: 1_820,
            durationSeconds: 150,
            sampleCount: 7_500,
            splitCurve: nil,
            trackingIntegrity: .verified,
            stepCorrections: [],
            heartRateBuffer: HeartRateSessionSampleBuffer(restoring: resumedViewModel.heartRateSamplesSnapshot)
        )
        let resumedWorkout = ActiveHeadphoneWorkoutDraftSaver.makeRecoveredWorkout(
            from: persistedDraft,
            deviceModel: "iPhone"
        )

        #expect(recoveredWorkout.heartRateTimeSeries.count == 90)
        #expect(resumedWorkout.heartRateTimeSeries.count == 150)

        // --- Evidence 1: the surface a user actually sees ---------------------
        let proof = EvidenceSheet(recovered: recoveredWorkout, resumed: resumedWorkout)
        let renderer = ImageRenderer(content: proof)
        renderer.scale = 3
        let image = try #require(renderer.uiImage, "ImageRenderer produced no image")
        let png = try #require(image.pngData(), "UIImage produced no PNG data")
        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        try png.write(
            to: URL(filePath: directory).appending(path: "recovered-heart-rate-workout-detail.png")
        )

        // --- Evidence 2: the persisted state behind that surface -------------
        let dump = EvidenceDump(
            recoveredSave: .init(workout: recoveredWorkout, startedAt: Self.startedAt),
            resumedSave: .init(workout: resumedWorkout, startedAt: Self.startedAt)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(dump).write(
            to: URL(filePath: directory).appending(path: "recovered-heart-rate-persisted-state.json")
        )

        #expect(png.count > 5_000)
    }

    private func makeDraft() -> ActiveHeadphoneWorkoutDraft {
        ActiveHeadphoneWorkoutDraft(
            sessionID: "heart-rate-evidence",
            kind: .justClimb,
            startedAt: Self.startedAt,
            title: "Just Climb",
            subtitle: "Open session",
            workoutName: "Just Climb",
            targetStepCount: nil,
            targetDurationSeconds: nil
        )
    }
}

private struct EvidenceDump: Encodable {
    struct Save: Encodable {
        let sampleCount: Int
        let avgHeartRate: Int?
        let maxHeartRate: Int?
        let firstSampleElapsedSeconds: TimeInterval?
        let lastSampleElapsedSeconds: TimeInterval?
        let workoutDurationSeconds: TimeInterval
        let heartRateCoverage: HeartRateTraceCoverage?
        let sampleTimelineHeadAndTail: [String]

        init(workout: Workout, startedAt: Date) {
            let series = workout.heartRateTimeSeries
            sampleCount = series.count
            avgHeartRate = workout.avgHeartRate
            maxHeartRate = workout.maxHeartRate
            firstSampleElapsedSeconds = series.first?.timestamp.timeIntervalSince(startedAt)
            lastSampleElapsedSeconds = series.last?.timestamp.timeIntervalSince(startedAt)
            workoutDurationSeconds = workout.duration
            heartRateCoverage = workout.sourceMetadata
                .flatMap { try? JSONDecoder().decode(HeadphoneMotionWorkoutMetadata.self, from: Data($0.utf8)) }?
                .heartRateCoverage
            let described = series.map { sample in
                "t+\(Int(sample.timestamp.timeIntervalSince(startedAt)))s = \(sample.heartRate) bpm"
            }
            sampleTimelineHeadAndTail = described.count > 8
                ? Array(described.prefix(4)) + ["…"] + Array(described.suffix(4))
                : described
        }
    }

    let recoveredSave: Save
    let resumedSave: Save
}

/// Panel 1 annotates the pre-fix outcome (the Heart Rate section simply never
/// rendered, because the recovered `Workout` carried no series). Panels 2 and 3
/// are the shipping `HeartRateChartView` fed by the real recovered/resumed
/// `Workout` objects built above.
private struct EvidenceSheet: View {
    let recovered: Workout
    let resumed: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text("Workout Detail - Heart Rate section")
                .font(.montserratBold(size: 24))
                .foregroundStyle(.white)

            panel("BEFORE - recovered session (old behavior)") {
                VStack(spacing: 10) {
                    Image(systemName: "heart.slash")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Heart Rate section absent - 0 samples, no avg, no max")
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                        .foregroundStyle(.white.opacity(0.25))
                )
            }

            panel("AFTER - saved straight from the recovery prompt") {
                chart(for: recovered)
            }

            panel("AFTER - resumed after the interruption (one continuous series)") {
                chart(for: resumed)
            }
        }
        .padding(28)
        .frame(width: 760)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }

    private func chart(for workout: Workout) -> some View {
        HeartRateChartView(
            heartRateData: workout.heartRateTimeSeries,
            workoutStartTime: workout.date,
            workoutDuration: workout.duration,
            averageHeartRateBpm: workout.avgHeartRate,
            maxHeartRateBpm: workout.maxHeartRate
        )
        .frame(height: 230)
    }

    private func panel(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.montserratSemiBold(size: 13))
                .foregroundStyle(Color(hex: "86D30A"))
            content()
        }
    }
}
