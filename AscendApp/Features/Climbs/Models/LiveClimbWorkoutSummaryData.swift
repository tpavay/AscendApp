import Foundation

struct LiveClimbProgressPoint: Identifiable, Equatable {
    let elapsedSeconds: Int
    let steps: Int

    var id: String {
        "\(elapsedSeconds)-\(steps)"
    }
}

struct LiveClimbPaceSplit: Identifiable, Equatable {
    let index: Int
    let startElapsedSeconds: Int
    let endElapsedSeconds: Int
    let steps: Int
    let stepsPerMinute: Double

    var id: Int { index }

    var durationSeconds: Int {
        max(endElapsedSeconds - startElapsedSeconds, 1)
    }
}

enum LiveClimbWorkoutSummaryData {
    private static let maxReplaySplitCheckpoints = 360

    static func metadata(for workout: Workout) -> HeadphoneMotionWorkoutMetadata? {
        guard workout.source == .headphoneMotion,
              let sourceMetadata = workout.sourceMetadata,
              let data = sourceMetadata.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(HeadphoneMotionWorkoutMetadata.self, from: data)
    }

    @MainActor
    static func climb(for workout: Workout) -> Climb? {
        guard let climbId = metadata(for: workout)?.climbId else { return nil }
        return try? ClimbService.shared.climb(for: climbId)
    }

    /// The step scale a finished session's summary is drawn against: the recorder's
    /// own target, never below what the session actually logged.
    static func summaryTargetSteps(metadata: HeadphoneMotionWorkoutMetadata, workout: Workout) -> Int {
        max(metadata.targetStepCount ?? workout.steps, workout.steps, 1)
    }

    static func progressPoints(for workout: Workout, targetSteps: Int) -> [LiveClimbProgressPoint] {
        normalizedProgressPoints(for: workout, targetSteps: targetSteps)
    }

    static func paceSplits(for workout: Workout, targetSteps: Int) -> [LiveClimbPaceSplit] {
        let durationSeconds = max(Int(workout.duration.rounded(.down)), 1)
        let splitDurationSeconds = paceSplitDurationSeconds(for: durationSeconds)
        let points = normalizedProgressPoints(for: workout, targetSteps: targetSteps)

        var splits: [LiveClimbPaceSplit] = []
        var startElapsedSeconds = 0

        while startElapsedSeconds < durationSeconds {
            let endElapsedSeconds = min(startElapsedSeconds + splitDurationSeconds, durationSeconds)
            let startSteps = cumulativeSteps(at: startElapsedSeconds, in: points)
            let endSteps = cumulativeSteps(at: endElapsedSeconds, in: points)
            let steps = max(endSteps - startSteps, 0)
            let splitDurationMinutes = Double(max(endElapsedSeconds - startElapsedSeconds, 1)) / 60

            splits.append(
                LiveClimbPaceSplit(
                    index: splits.count,
                    startElapsedSeconds: startElapsedSeconds,
                    endElapsedSeconds: endElapsedSeconds,
                    steps: steps,
                    stepsPerMinute: Double(steps) / splitDurationMinutes
                )
            )

            startElapsedSeconds = endElapsedSeconds
        }

        if splits.isEmpty {
            return [
                LiveClimbPaceSplit(
                    index: 0,
                    startElapsedSeconds: 0,
                    endElapsedSeconds: durationSeconds,
                    steps: max(workout.steps, 0),
                    stepsPerMinute: workout.stepsPerMinute ?? 0
                )
            ]
        }

        return splits
    }

    static func paceSplitDurationSeconds(for durationSeconds: Int) -> Int {
        switch max(durationSeconds, 1) {
        case ...600:
            return 60
        case ...1_200:
            return 120
        case ...2_700:
            return 300
        default:
            return 600
        }
    }

    private static func normalizedProgressPoints(for workout: Workout, targetSteps: Int) -> [LiveClimbProgressPoint] {
        let resolvedTargetSteps = max(targetSteps, workout.steps, 1)
        let durationSeconds = max(Int(workout.duration.rounded(.down)), 1)
        let metadata = metadata(for: workout)
        let intervalSeconds = max(metadata?.splitIntervalSeconds ?? 0, 0)
        let splitSteps = metadata?.splitSteps ?? []

        var points: [LiveClimbProgressPoint]
        if intervalSeconds > 0, !splitSteps.isEmpty {
            let normalizedSteps = normalizedSplitSteps(
                splitSteps,
                intervalSeconds: intervalSeconds,
                finalDurationSeconds: durationSeconds,
                finalSteps: max(workout.steps, 0)
            )
            let finalBucketIndex = splitBucketIndex(
                for: durationSeconds,
                intervalSeconds: intervalSeconds
            )
            points = normalizedSteps.enumerated().map { index, steps in
                LiveClimbProgressPoint(
                    elapsedSeconds: splitElapsedSeconds(
                        forBucketIndex: index,
                        intervalSeconds: intervalSeconds,
                        finalDurationSeconds: durationSeconds,
                        finalBucketIndex: finalBucketIndex
                    ),
                    steps: min(max(steps, 0), resolvedTargetSteps)
                )
            }
        } else {
            points = []
        }

        // Workout progress at elapsed zero is zero, whatever a recovered or legacy curve stored.
        points.removeAll { $0.elapsedSeconds == 0 }
        points.insert(LiveClimbProgressPoint(elapsedSeconds: 0, steps: 0), at: 0)

        if points.last?.elapsedSeconds != durationSeconds || points.last?.steps != workout.steps {
            points.append(
                LiveClimbProgressPoint(
                    elapsedSeconds: durationSeconds,
                    steps: min(max(workout.steps, 0), resolvedTargetSteps)
                )
            )
        }

        return normalized(points)
    }

    private static func splitBucketIndex(for elapsedSeconds: Int, intervalSeconds: Int) -> Int {
        max(elapsedSeconds, 0) / max(intervalSeconds, 1)
    }

    /// A bucket is interpreted at the end of its window, not its start - see
    /// `LiveReplaySplitCurve` for the anchoring contract this places points against.
    private static func splitElapsedSeconds(
        forBucketIndex index: Int,
        intervalSeconds: Int,
        finalDurationSeconds: Int,
        finalBucketIndex: Int
    ) -> Int {
        let safeDurationSeconds = max(finalDurationSeconds, 1)
        guard index < finalBucketIndex else { return safeDurationSeconds }

        let bucketEndSeconds = (max(index, 0) + 1) * max(intervalSeconds, 1)
        return min(bucketEndSeconds, safeDurationSeconds)
    }

    /// Twin of the server's `normalizeReplaySplitSteps`. Both sides are pinned to the same
    /// end-anchored bucket contract by `SharedTestVectors/live-replay-split-normalization-vector.json`,
    /// so this stays module-visible for that parity test rather than private.
    static func normalizedSplitSteps(
        _ splitSteps: [Int],
        intervalSeconds: Int,
        finalDurationSeconds: Int,
        finalSteps: Int
    ) -> [Int] {
        let resolvedFinalSteps = max(finalSteps, 0)
        let resolvedIntervalSeconds = max(intervalSeconds, 1)
        let expectedFinalBucketIndex = max(finalDurationSeconds / resolvedIntervalSeconds, 0)
        let bucketCount = min(
            max(splitSteps.count, expectedFinalBucketIndex + 1),
            maxReplaySplitCheckpoints
        )
        var clampedSteps = monotonicClampedSteps(
            splitSteps,
            bucketCount: bucketCount,
            finalSteps: resolvedFinalSteps
        )

        if shouldReconstructCurve(
            clampedSteps,
            expectedFinalBucketIndex: expectedFinalBucketIndex,
            intervalSeconds: resolvedIntervalSeconds,
            finalDurationSeconds: finalDurationSeconds,
            finalSteps: resolvedFinalSteps
        ) {
            var reconstructedSteps = reconstructedLinearCurve(
                bucketCount: bucketCount,
                intervalSeconds: resolvedIntervalSeconds,
                finalDurationSeconds: finalDurationSeconds,
                finalSteps: resolvedFinalSteps
            )
            if expectedFinalBucketIndex < reconstructedSteps.count {
                reconstructedSteps[expectedFinalBucketIndex] = resolvedFinalSteps
            }
            return reconstructedSteps
        }

        if expectedFinalBucketIndex < clampedSteps.count {
            clampedSteps[expectedFinalBucketIndex] = max(
                clampedSteps[expectedFinalBucketIndex],
                resolvedFinalSteps
            )
        }

        return clampedSteps
    }

    private static func monotonicClampedSteps(
        _ splitSteps: [Int],
        bucketCount: Int,
        finalSteps: Int
    ) -> [Int] {
        var steps: [Int] = []
        var lastStep = 0

        for index in 0..<bucketCount {
            let rawStep = index < splitSteps.count ? splitSteps[index] : lastStep
            lastStep = min(max(rawStep, lastStep, 0), finalSteps)
            steps.append(lastStep)
        }

        return steps
    }

    private static func shouldReconstructCurve(
        _ steps: [Int],
        expectedFinalBucketIndex: Int,
        intervalSeconds: Int,
        finalDurationSeconds: Int,
        finalSteps: Int
    ) -> Bool {
        guard finalSteps > 0,
              finalDurationSeconds >= intervalSeconds * 2,
              steps.count >= 3 else {
            return false
        }

        let finalBucketIndex = min(expectedFinalBucketIndex, steps.count - 1)
        let stepsBeforeFinalBucket = steps.prefix(finalBucketIndex)
        let hasIntermediateProgress = stepsBeforeFinalBucket.contains { step in
            step > 0 && step < finalSteps
        }

        return !hasIntermediateProgress && steps[finalBucketIndex] >= finalSteps
    }

    private static func reconstructedLinearCurve(
        bucketCount: Int,
        intervalSeconds: Int,
        finalDurationSeconds: Int,
        finalSteps: Int
    ) -> [Int] {
        let safeDurationSeconds = max(finalDurationSeconds, 1)
        var steps: [Int] = []
        var lastStep = 0

        for index in 0..<bucketCount {
            // Bucket `index` is read at the end of its window, so it projects the
            // progress reached by `(index + 1) * intervalSeconds`.
            let elapsedSeconds = (index + 1) * intervalSeconds
            let progress = min(Double(elapsedSeconds) / Double(safeDurationSeconds), 1)
            let projectedStep = elapsedSeconds >= safeDurationSeconds
                ? finalSteps
                : Int((Double(finalSteps) * progress).rounded())
            lastStep = min(max(projectedStep, lastStep), finalSteps)
            steps.append(lastStep)
        }

        return steps
    }

    private static func cumulativeSteps(at elapsedSeconds: Int, in points: [LiveClimbProgressPoint]) -> Int {
        let resolvedElapsedSeconds = max(elapsedSeconds, 0)
        guard let firstPoint = points.first else { return 0 }

        if resolvedElapsedSeconds <= firstPoint.elapsedSeconds {
            return firstPoint.steps
        }

        for (previousPoint, nextPoint) in zip(points, points.dropFirst()) {
            guard resolvedElapsedSeconds <= nextPoint.elapsedSeconds else { continue }
            let intervalSeconds = max(nextPoint.elapsedSeconds - previousPoint.elapsedSeconds, 1)
            let elapsedInInterval = resolvedElapsedSeconds - previousPoint.elapsedSeconds
            let progress = min(max(Double(elapsedInInterval) / Double(intervalSeconds), 0), 1)
            let interpolatedSteps = Double(previousPoint.steps) +
                (Double(nextPoint.steps - previousPoint.steps) * progress)
            return Int(interpolatedSteps.rounded())
        }

        return points.last?.steps ?? firstPoint.steps
    }

    private static func normalized(_ points: [LiveClimbProgressPoint]) -> [LiveClimbProgressPoint] {
        let sortedPoints = points.sorted { lhs, rhs in
            if lhs.elapsedSeconds == rhs.elapsedSeconds {
                return lhs.steps < rhs.steps
            }
            return lhs.elapsedSeconds < rhs.elapsedSeconds
        }

        var highestSteps = 0
        var deduped: [LiveClimbProgressPoint] = []

        for point in sortedPoints {
            highestSteps = max(highestSteps, point.steps)

            if deduped.last?.elapsedSeconds == point.elapsedSeconds {
                deduped[deduped.count - 1] = LiveClimbProgressPoint(
                    elapsedSeconds: point.elapsedSeconds,
                    steps: highestSteps
                )
            } else {
                deduped.append(
                    LiveClimbProgressPoint(
                        elapsedSeconds: point.elapsedSeconds,
                        steps: highestSteps
                    )
                )
            }
        }

        return deduped.isEmpty ? [LiveClimbProgressPoint(elapsedSeconds: 0, steps: 0)] : deduped
    }
}
