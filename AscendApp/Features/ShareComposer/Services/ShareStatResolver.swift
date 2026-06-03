import Foundation

/// Resolves canonical workout + climb data into display-ready share stats.
///
/// Pure value type (no SwiftUI, no side effects) so the stat catalog and its
/// formatting are unit-testable without a view tree — per CLAUDE.md's
/// testability and "stat values are read from canonical data, never recomputed
/// or stored on a share model" rules.
struct ShareStatResolver {
    let workout: Workout
    let measurementSystem: MeasurementSystem
    let stepHeight: Double
    var climbName: String?
    var climbRank: Int?
    var climbRankTotal: Int?

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
            let name = workout.name.isEmpty ? "Stair Workout" : workout.name
            return ResolvedShareStat(kind: kind, label: "ASCEND", value: name)

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

        case .climbName:
            guard let climbName else { return nil }
            return ResolvedShareStat(kind: kind, label: "CLIMB", value: climbName)

        case .climbRank:
            guard let climbRank, climbRank > 0 else { return nil }
            return ResolvedShareStat(kind: kind, label: "FINISHER", value: "#\(climbRank)")

        case .bestEffort:
            // Best Effort isn't on the Workout — it's injected into the view
            // model from the Best Effort cache. The resolver can't produce it.
            return nil
        }
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
}
