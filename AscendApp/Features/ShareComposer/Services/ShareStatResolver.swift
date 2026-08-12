import Foundation

/// Resolves canonical workout + climb data into display-ready share stats.
///
/// Pure value type (no SwiftUI, no side effects) so the stat catalog and its
/// formatting are unit-testable without a view tree — per CLAUDE.md's
/// testability rule and the `ascend-share-composer` skill's "stat values are
/// read from canonical data, never recomputed or stored on a share model" rule.
struct ShareStatResolver {
    let workout: Workout
    let measurementSystem: MeasurementSystem
    let stepHeight: Double
    var climbName: String?
    var climbLocation: String? = nil
    var climbFloors: Int? = nil
    var climbRank: Int?
    var climbRankTotal: Int?
    var splitTargetSteps: Int?

    var isClimb: Bool { climbName != nil }

    /// The catalog filtered to stats that actually have a value for this workout.
    func availableKinds() -> [ShareStatStickerKind] {
        ShareStatStickerKind.allCases.filter { kind in
            if kind.isClimbOnly && !isClimb { return false }
            return resolve(kind) != nil
        }
    }

    /// Resolve a single stat. Returns nil when the workout has no value for it.
    func resolve(_ kind: ShareStatStickerKind) -> ResolvedShareStat? {
        switch kind {
        case .workoutName:
            // For climbs the dedicated climb-name sticker covers this, so don't
            // offer a duplicate. The "ASCEND" branding lives only in the
            // always-on bottom wordmark, never tied to a stat.
            if isClimb { return nil }
            let name = workout.name.isEmpty ? "Stair Workout" : workout.name
            return ResolvedShareStat(kind: kind, label: "WORKOUT", value: name)

        case .date:
            return ResolvedShareStat(kind: kind, label: "DATE", value: Self.dateFormatter.string(from: workout.date))

        case .duration:
            return ResolvedShareStat(kind: kind, label: "DURATION", value: workout.durationFormatted)

        case .steps:
            guard workout.steps > 0 else { return nil }
            return ResolvedShareStat(kind: kind, label: "STEPS", value: Self.integer(workout.steps))

        case .calories:
            guard let cal = workout.caloriesBurned, cal > 0 else { return nil }
            return ResolvedShareStat(kind: kind, label: "CAL", value: Self.integer(cal))

        case .pace:
            guard let spm = workout.stepsPerMinute, spm > 0 else { return nil }
            return ResolvedShareStat(kind: kind, label: "SPM", value: Self.decimal(spm, 1))

        case .avgHeartRate:
            guard let hr = workout.avgHeartRate, hr > 0 else { return nil }
            return ResolvedShareStat(kind: kind, label: "AVG BPM", value: "\(hr)")

        case .maxHeartRate:
            guard let hr = workout.maxHeartRate, hr > 0 else { return nil }
            return ResolvedShareStat(kind: kind, label: "MAX BPM", value: "\(hr)")

        case .verticalClimb:
            guard workout.steps > 0 else { return nil }
            let vertical = workout.totalVerticalClimb(stepHeight: stepHeight, measurementSystem: measurementSystem)
            let value = Self.decimal(vertical, vertical < 100 ? 1 : 0)
            return ResolvedShareStat(kind: kind, label: "VERTICAL", value: "\(value) \(measurementSystem.distanceAbbreviation)")

        case .addedWeight:
            guard workout.hasWeights else { return nil }
            let weight = workout.totalWeightUsed
            let formatted = weight.truncatingRemainder(dividingBy: 1) == 0
                ? Self.decimal(weight, 0)
                : Self.decimal(weight, 1)
            return ResolvedShareStat(kind: kind, label: "ADDED", value: "\(formatted) \(measurementSystem.weightAbbreviation)")

        case .splits:
            guard let splits = resolveSplits() else { return nil }
            return ResolvedShareStat(kind: kind, label: splits.label, value: splits.value, detail: splits.subtitle)

        case .climbName:
            guard let climbName else { return nil }
            return ResolvedShareStat(kind: kind, label: "LANDMARK", value: climbName)

        case .climbLocation:
            guard let climbLocation else { return nil }
            return ResolvedShareStat(kind: kind, label: "LOCATION", value: climbLocation)

        case .climbFloors:
            guard let climbFloors, climbFloors > 0 else { return nil }
            return ResolvedShareStat(kind: kind, label: "FLOORS", value: Self.integer(climbFloors))

        case .climbRank:
            guard let climbRank, climbRank > 0 else { return nil }
            return ResolvedShareStat(kind: kind, label: "RANK", value: "#\(climbRank)")

        case .climbRankWithTotal:
            guard let climbRank, climbRank > 0,
                  let climbRankTotal, climbRankTotal > 0 else { return nil }
            return ResolvedShareStat(
                kind: kind,
                label: "RANK / TOTAL",
                value: "#\(climbRank) / \(Self.integer(climbRankTotal))",
                detail: Self.integer(climbRankTotal)
            )

        case .bestEffort, .totals:
            // Injected stats: Best Effort comes from the Best Effort cache and
            // Totals from this-week aggregates. Neither is resolvable from a
            // single Workout, so the view model supplies them.
            return nil
        }
    }

    /// Resolve live sampled progress into split rows for the share sticker.
    /// Total-only/manual workouts do not get this even though split math could be
    /// reconstructed, because splits should reflect recorded timeline data.
    func resolveSplits() -> ResolvedShareSplits? {
        guard let metadata = Self.recordedSplitMetadata(for: workout) else { return nil }

        let timelineTargetSteps = max(
            splitTargetSteps ?? metadata.climbTargetStepCount ?? metadata.targetStepCount ?? workout.steps,
            workout.steps,
            1
        )
        let splits = LiveClimbWorkoutSummaryData.paceSplits(
            for: workout,
            targetSteps: timelineTargetSteps
        )
        guard !splits.isEmpty else { return nil }

        let minSPM = splits.map(\.stepsPerMinute).min() ?? 0
        let maxSPM = max(splits.map(\.stepsPerMinute).max() ?? 0, 1)
        let rows = splits.map { split in
            ResolvedShareSplitRow(
                index: split.index,
                segmentText: "\(split.index + 1)",
                rangeText: "\(Self.clockTime(split.startElapsedSeconds))-\(Self.clockTime(split.endElapsedSeconds))",
                stepsText: Self.integer(split.steps),
                spmText: "\(Int(split.stepsPerMinute.rounded()).formatted())",
                heartRateText: averageHeartRateText(for: split),
                progress: Self.normalizedSplitProgress(
                    split.stepsPerMinute,
                    minStepsPerMinute: minSPM,
                    maxStepsPerMinute: maxSPM
                )
            )
        }
        let hasHeartRate = rows.contains { $0.heartRateText != nil }
        let segmentText = "\(rows.count.formatted()) \(rows.count == 1 ? "SEGMENT" : "SEGMENTS")"
        let averageText = workout.stepsPerMinute.map { "\(Int($0.rounded()).formatted()) SPM AVG" } ?? "SPM SPLITS"

        return ResolvedShareSplits(
            label: "SPLITS",
            value: segmentText,
            subtitle: "\(segmentText) · \(averageText)",
            rows: rows,
            stepQuintileRows: stepQuintileRows(recordedSteps: max(workout.steps, 0)),
            averageStepsPerMinuteText: workout.stepsPerMinute.map { Self.decimal($0, 1) } ?? "0.0",
            hasHeartRate: hasHeartRate
        )
    }

    /// Builds five equal step ranges and interpolates the recorded progress
    /// curve to find how long each range took.
    ///
    /// The ranges span the steps this attempt actually recorded, never the
    /// tower's reference count: an attempt that stopped short has no recorded
    /// pace past where it stopped, and ranging over the tower invented rows that
    /// read as a single second at an impossible pace.
    private func stepQuintileRows(recordedSteps: Int) -> [ResolvedShareSplitRow] {
        guard recordedSteps >= 5 else { return [] }

        let points = LiveClimbWorkoutSummaryData.progressPoints(for: workout, targetSteps: recordedSteps)
        guard points.count >= 2 else { return [] }

        let baseSteps = recordedSteps / 5
        let average = workout.stepsPerMinute ?? 0
        var rows: [ResolvedShareSplitRow] = []

        for index in 0..<5 {
            let startStep = index * baseSteps + 1
            let endStep = index == 4 ? recordedSteps : (index + 1) * baseSteps
            let blockSteps = endStep - startStep + 1
            let startElapsed = elapsedSeconds(atCumulativeSteps: startStep - 1, points: points)
            let endElapsed = elapsedSeconds(atCumulativeSteps: endStep, points: points)
            let duration = max(endElapsed - startElapsed, 1)
            let stepsPerMinute = Double(blockSteps) / (Double(duration) / 60)

            rows.append(
                ResolvedShareSplitRow(
                    index: index,
                    segmentText: "\(index + 1)",
                    rangeText: "\(startStep)-\(endStep)",
                    stepsText: Self.integer(blockSteps),
                    spmText: Self.decimal(stepsPerMinute, 1),
                    heartRateText: nil,
                    elapsedText: Self.clockTime(duration),
                    isFasterThanAverage: stepsPerMinute > average,
                    progress: stepsPerMinute
                )
            )
        }

        let fastest = max(rows.map(\.progress).max() ?? 0, 1)
        return rows.map { row in
            ResolvedShareSplitRow(
                index: row.index,
                segmentText: row.segmentText,
                rangeText: row.rangeText,
                stepsText: row.stepsText,
                spmText: row.spmText,
                heartRateText: nil,
                elapsedText: row.elapsedText,
                isFasterThanAverage: row.isFasterThanAverage,
                progress: row.progress / fastest
            )
        }
    }

    private func elapsedSeconds(
        atCumulativeSteps targetSteps: Int,
        points: [LiveClimbProgressPoint]
    ) -> Int {
        guard targetSteps > 0 else { return 0 }
        guard let upperIndex = points.firstIndex(where: { $0.steps >= targetSteps }) else {
            return max(Int(workout.duration.rounded()), 1)
        }
        guard upperIndex > 0 else { return points[upperIndex].elapsedSeconds }

        let lower = points[upperIndex - 1]
        let upper = points[upperIndex]
        let stepSpan = upper.steps - lower.steps
        guard stepSpan > 0 else { return upper.elapsedSeconds }

        let fraction = Double(targetSteps - lower.steps) / Double(stepSpan)
        let elapsedSpan = upper.elapsedSeconds - lower.elapsedSeconds
        return lower.elapsedSeconds + Int((Double(elapsedSpan) * fraction).rounded())
    }

    // MARK: - Formatting

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static func integer(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    private static func decimal(_ value: Double, _ places: Int) -> String {
        value.formatted(.number.precision(.fractionLength(places)))
    }

    private func averageHeartRateText(for split: LiveClimbPaceSplit) -> String? {
        let samples = workout.heartRateTimeSeries.filter { sample in
            let elapsed = sample.timestamp.timeIntervalSince(workout.date)
            return elapsed >= TimeInterval(split.startElapsedSeconds) &&
                elapsed <= TimeInterval(split.endElapsedSeconds) &&
                sample.heartRate > 0
        }
        guard !samples.isEmpty else { return nil }

        let average = Double(samples.reduce(0) { $0 + $1.heartRate }) / Double(samples.count)
        return "\(Int(average.rounded()).formatted())"
    }

    private static func recordedSplitMetadata(for workout: Workout) -> HeadphoneMotionWorkoutMetadata? {
        guard let metadata = LiveClimbWorkoutSummaryData.metadata(for: workout),
              let intervalSeconds = metadata.splitIntervalSeconds,
              intervalSeconds > 0,
              let splitSteps = metadata.splitSteps,
              splitSteps.count >= 2,
              splitSteps.contains(where: { $0 > 0 }) else {
            return nil
        }

        return metadata
    }

    private static func normalizedSplitProgress(
        _ stepsPerMinute: Double,
        minStepsPerMinute: Double,
        maxStepsPerMinute: Double
    ) -> Double {
        guard maxStepsPerMinute > minStepsPerMinute else { return 1 }

        let range = maxStepsPerMinute - minStepsPerMinute
        let normalized = min(max((stepsPerMinute - minStepsPerMinute) / range, 0), 1)
        return 0.25 + (normalized * 0.75)
    }

    private static func clockTime(_ seconds: Int) -> String {
        let totalSeconds = max(seconds, 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(minutes < 10 ? "0" : "")\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
        }

        return "\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
    }
}
