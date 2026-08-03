import Foundation
import Testing
@testable import AscendApp

/// Measures what a gesture frame costs on the composer canvas, before and after,
/// and writes the proof to disk.
///
/// The canvas resolved every sticker's stats inside `body`, and `body` re-runs on
/// every frame of a drag because the drag itself mutates observed state
/// (`draggingID`, the snap guides, the trash flag). Resolving splits filters the
/// whole heart-rate series once per split, so that was unbounded
/// O(samples × splits) work per sticker per frame — a live `CLAUDE.md`
/// violation: "Render path stays cheap."
///
/// `before` reconstructs exactly what the old render path did: build a
/// `ShareStatResolver` (it was a computed property, so a new one per access) and
/// resolve the sticker's stats and splits. `after` calls the shipping path.
///
/// The wall-clock numbers are printed for the record. The single assertion is a
/// ~100× structural margin — 120 frames of the new path against **one** frame of
/// the old — which cannot flake on a loaded runner but fails outright if the
/// memoization is removed.
@MainActor
struct ShareComposerGestureCostEvidenceTests {
    private static let start = Date(timeIntervalSince1970: 1_750_300_000)
    private static let sampleCount = 1_200
    private static let splitCount = 10
    /// A drag at 120 Hz for a second.
    private static let frames = 120

    @Test
    func aGestureFrameNoLongerReDerivesEveryStat() throws {
        let workout = Self.liveClimbWorkout()
        let viewModel = Self.makeViewModel(workout: workout)

        var sticker = ShareStickerInstance(kind: .steps, labelPlacement: .below)
        sticker.extraStats = [
            ShareStatRef(kind: .duration),
            ShareStatRef(kind: .calories),
            ShareStatRef(kind: .avgHeartRate)
        ]
        viewModel.stickers = [sticker]
        let splitsSticker = ShareStickerInstance(kind: .splits)

        // One frame of the old render path, for both stickers on the canvas.
        // Taken as a median: the first call also pays for one-time formatter
        // setup, and quoting that as the per-frame cost would overstate it.
        let beforeOneFrame = Self.medianDuration(over: 9) {
            _ = Self.legacyResolvedStats(for: sticker, workout: workout)
            _ = Self.legacyResolvedSplits(for: splitsSticker, workout: workout)
        }

        // Warm the cache the way opening the composer does, then drag.
        viewModel.stickers.append(splitsSticker)
        _ = viewModel.content(for: sticker)
        _ = viewModel.content(for: splitsSticker)

        let afterAllFrames = Self.duration {
            for frame in 0..<Self.frames {
                // A drag changes only the transform.
                viewModel.stickers[0].position = CGPoint(x: 0.5, y: 0.2 + Double(frame) / 1_000)
                for placed in viewModel.stickers {
                    _ = viewModel.content(for: placed)
                }
            }
        }

        let beforeAllFrames = beforeOneFrame * Double(Self.frames)
        let report = """
        Share composer gesture cost (\(Self.sampleCount) heart-rate samples, \(Self.splitCount) splits, \
        2 stickers, \(Self.frames) frames)

          before  \(Self.milliseconds(beforeOneFrame)) ms per frame \
        (\(Self.milliseconds(beforeAllFrames)) ms for \(Self.frames) frames)
          after   \(Self.milliseconds(afterAllFrames / Double(Self.frames))) ms per frame \
        (\(Self.milliseconds(afterAllFrames)) ms for \(Self.frames) frames)

          120 Hz frame budget: 8.3 ms · 60 Hz frame budget: 16.7 ms
        """
        print(report)
        Self.writeEvidence(report)

        #expect(
            afterAllFrames < beforeOneFrame,
            """
            \(Self.frames) frames of the new path must cost less than one frame of the old.
            \(report)
            """
        )

        // The structural guarantee behind the number: a transform-only change
        // reuses the built card rather than rebuilding it.
        let first = viewModel.content(for: viewModel.stickers[0])
        viewModel.stickers[0].scale = 2.4
        viewModel.stickers[0].rotationRadians = 0.3
        let afterTransform = viewModel.content(for: viewModel.stickers[0])
        #expect(first == afterTransform, "pan, pinch and rotate must not rebuild the card")

        // Content changes must still rebuild it.
        viewModel.setLabelPlacement(.leading, for: viewModel.stickers[0].id)
        let afterPlacement = viewModel.content(for: viewModel.stickers[0])
        #expect(first != afterPlacement, "moving the labels must rebuild the card")
    }

    // MARK: - The old render path, reconstructed

    /// What `ShareComposerViewModel.resolvedStats(for:)` did: a fresh
    /// `ShareStatResolver` per access, resolving each ref from scratch.
    private static func legacyResolvedStats(
        for instance: ShareStickerInstance,
        workout: Workout
    ) -> [ResolvedShareStat] {
        instance.statRefs.compactMap { ref in
            legacyResolver(workout: workout).resolve(ref.kind)
        }
    }

    private static func legacyResolvedSplits(
        for instance: ShareStickerInstance,
        workout: Workout
    ) -> ResolvedShareSplits? {
        guard instance.kind == .splits, instance.extraStats.isEmpty else { return nil }
        return legacyResolver(workout: workout).resolveSplits()
    }

    private static func legacyResolver(workout: Workout) -> ShareStatResolver {
        ShareStatResolver(
            workout: workout,
            measurementSystem: .imperial,
            stepHeight: MeasurementSystem.imperial.defaultStepHeight,
            climbName: "Empire State Building",
            climbRank: 7,
            climbRankTotal: 2_460,
            splitTargetSteps: 1_800
        )
    }

    // MARK: - Fixtures

    private static func makeViewModel(workout: Workout) -> ShareComposerViewModel {
        ShareComposerViewModel(
            workout: workout,
            measurementSystem: .imperial,
            stepHeight: MeasurementSystem.imperial.defaultStepHeight,
            climbName: "Empire State Building",
            climbRank: 7,
            climbRankTotal: 2_460
        )
    }

    private static func liveClimbWorkout() -> Workout {
        let stepsPerSplit = 180
        let splitCurve = LiveReplaySplitCurve(
            intervalSeconds: 30,
            steps: (1...splitCount).map { $0 * stepsPerSplit }
        )
        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: sampleCount,
            climbId: "empire-state-building",
            targetStepCount: stepsPerSplit * splitCount,
            stopReason: .targetReached,
            splitCurve: splitCurve
        )
        let series = (0..<sampleCount).map { index in
            HeartRateDataPoint(
                timestamp: start.addingTimeInterval(Double(index) * 0.25),
                heartRate: 130 + index % 40
            )
        }

        return Workout(
            name: "Live Climb",
            date: start,
            duration: TimeInterval(splitCount * 30),
            steps: stepsPerSplit * splitCount,
            floors: Workout.stepsToFloors(stepsPerSplit * splitCount, stepsPerFloor: 16),
            caloriesBurned: 317,
            heartRateTimeSeries: series,
            source: .headphoneMotion,
            sourceMetadata: metadata.jsonString
        )
    }

    // MARK: - Measurement

    private static func medianDuration(over iterations: Int, of work: () -> Void) -> Double {
        let samples = (0..<iterations).map { _ in duration(of: work) }.sorted()
        return samples[samples.count / 2]
    }

    private static func duration(of work: () -> Void) -> Double {
        let started = ContinuousClock.now
        work()
        let elapsed = ContinuousClock.now - started
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    private static func milliseconds(_ seconds: Double) -> String {
        String(format: "%.4f", seconds * 1_000)
    }

    private static func writeEvidence(_ report: String) {
        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            .map { URL(filePath: $0) } ?? FileManager.default.temporaryDirectory
        let url = directory.appending(path: "share-composer-gesture-cost.txt")
        try? report.write(to: url, atomically: true, encoding: .utf8)
        print("evidence: \(url.path())")
    }
}
