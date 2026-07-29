import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import AscendApp

/// Renders the real Splits surface from a recorded live-climb split curve so the
/// reconciliation contract is verifiable as the user sees it, not just as numbers.
@MainActor
struct LiveClimbPaceSplitEvidenceTests {
    private static let intervalSeconds = 10
    private static let durationSeconds = 930

    @Test
    func splitsCardReconcilesWithTheRecordedClimb() throws {
        let workout = Self.makeRecordedLiveClimbWorkout()
        let splits = LiveClimbWorkoutSummaryData.paceSplits(
            for: workout,
            targetSteps: workout.steps
        )

        let transcript = Self.transcript(for: workout, splits: splits)
        let transcriptURL = FileManager.default.temporaryDirectory
            .appending(path: "ascend-live-climb-splits.txt")
        try transcript.write(to: transcriptURL, atomically: true, encoding: .utf8)

        let imageURL = FileManager.default.temporaryDirectory
            .appending(path: "ascend-live-climb-splits-card.png")
        try Self.renderSplitsCard(splits: splits, workout: workout, to: imageURL)

        print("ASCEND_EVIDENCE_TRANSCRIPT=\(transcriptURL.path(percentEncoded: false))")
        print("ASCEND_EVIDENCE_IMAGE=\(imageURL.path(percentEncoded: false))")
        print(transcript)

        #expect(splits.reduce(0) { $0 + $1.steps } == workout.steps)
        #expect(splits.reduce(0) { $0 + $1.durationSeconds } == Self.durationSeconds)
        #expect(splits.first?.startElapsedSeconds == 0)
        #expect(splits.last?.endElapsedSeconds == Self.durationSeconds)

        for (split, nextSplit) in zip(splits, splits.dropFirst()) {
            #expect(split.endElapsedSeconds == nextSplit.startElapsedSeconds)
        }
    }

    // MARK: - Fixture

    /// A steady climb that ramps from roughly 66 SPM to 108 SPM, sampled the way
    /// `LiveReplaySplitSampler` records it: one cumulative checkpoint per 10s bucket.
    private static func recordedSplitSteps() -> [Int] {
        let finalBucketIndex = durationSeconds / intervalSeconds
        var cumulativeSteps = 0

        return (0...finalBucketIndex).map { bucket in
            let ramp = Double(bucket) / Double(finalBucketIndex)
            cumulativeSteps += Int((11 + 7 * ramp).rounded())
            return cumulativeSteps
        }
    }

    private static func makeRecordedLiveClimbWorkout() -> Workout {
        let splitSteps = recordedSplitSteps()
        let totalSteps = splitSteps.last ?? 0
        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: splitSteps.count,
            climbId: "eiffel-tower",
            targetStepCount: totalSteps,
            stopReason: .targetReached,
            splitCurve: LiveReplaySplitCurve(
                intervalSeconds: intervalSeconds,
                steps: splitSteps
            )
        )

        return Workout(
            name: "Live Climb",
            duration: TimeInterval(durationSeconds),
            steps: totalSteps,
            floors: Workout.stepsToFloors(totalSteps, stepsPerFloor: 16),
            stepsPerFloor: 16,
            source: .headphoneMotion,
            sourceMetadata: metadata.jsonString
        )
    }

    // MARK: - Artifacts

    private static func renderSplitsCard(
        splits: [LiveClimbPaceSplit],
        workout: Workout,
        to url: URL
    ) throws {
        let content = VStack(alignment: .leading, spacing: 16) {
            Text("\(workout.steps.formatted()) steps · 15:30 · \(splits.count) splits")
                .font(.montserratMedium(size: 12))
                .foregroundStyle(.white.opacity(0.54))

            WorkoutPaceSplitsSection(
                splits: splits,
                averageStepsPerMinute: workout.stepsPerMinute,
                effectiveColorScheme: .dark
            )
        }
        .padding(20)
        .frame(width: 402)
        .background(Color.black)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 3

        let image = try #require(renderer.cgImage)
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    private static func transcript(for workout: Workout, splits: [LiveClimbPaceSplit]) -> String {
        var lines = [
            "Live Climb — \(clockTime(durationSeconds)), \(workout.steps.formatted()) steps recorded",
            "Split curve: \(intervalSeconds)s buckets",
            "",
            "  #  window          steps    SPM"
        ]

        for split in splits {
            let window = "\(clockTime(split.startElapsedSeconds))-\(clockTime(split.endElapsedSeconds))"
            let steps = String(split.steps)
            let spm = String(Int(split.stepsPerMinute.rounded()))
            lines.append(
                "  \(String(split.index + 1))  \(window.padding(toLength: 14, withPad: " ", startingAt: 0))"
                + "  \(steps.padding(toLength: 7, withPad: " ", startingAt: 0))\(spm)"
            )
        }

        let splitStepTotal = splits.reduce(0) { $0 + $1.steps }
        let splitDurationTotal = splits.reduce(0) { $0 + $1.durationSeconds }
        lines.append("")
        lines.append("Sum of split steps:    \(splitStepTotal)  (workout total \(workout.steps))")
        lines.append("Sum of split seconds:  \(splitDurationTotal)  (workout duration \(durationSeconds))")

        return lines.joined(separator: "\n")
    }

    private static func clockTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return "\(minutes):\(remainder < 10 ? "0" : "")\(remainder)"
    }
}
