import Foundation

struct WorkoutEffortService {
    struct Analysis {
        let score: Double
        let equivalentLevel: Int?
        let paceScore: Double?
        let durationScore: Double
        let supportingScore: Double?

        var intensityTier: IntensityTier {
            IntensityTier.from(score: score)
        }
    }

    static func analyze(workout: Workout, baseLevel: Int) -> Analysis {
        let clampedBaseLevel = SPMMappingService.clampedLevel(baseLevel)
        let computedDurationScore = durationScore(for: workout.duration)
        let equivalentLevel = workout.stepsPerMinute.map { SPMMappingService.level(forSPM: $0) }
        let computedPaceScore = equivalentLevel.map { Self.paceScore(forLevel: $0, baseLevel: clampedBaseLevel) }
        let computedSupportingScore = supportingScore(for: workout)

        let finalScore: Double
        if let computedPaceScore {
            let weightedSupport = computedSupportingScore ?? computedDurationScore
            finalScore = clamp((computedPaceScore * 0.7) + (computedDurationScore * 0.2) + (weightedSupport * 0.1))
        } else if let computedSupportingScore {
            finalScore = clamp((computedSupportingScore * 0.7) + (computedDurationScore * 0.3))
        } else {
            finalScore = computedDurationScore
        }

        return Analysis(
            score: finalScore,
            equivalentLevel: equivalentLevel,
            paceScore: computedPaceScore,
            durationScore: computedDurationScore,
            supportingScore: computedSupportingScore
        )
    }

    static func paceScore(forLevel level: Int, baseLevel: Int) -> Double {
        let relativeOffset = Double(SPMMappingService.clampedLevel(level) - SPMMappingService.clampedLevel(baseLevel))
        let anchors: [(offset: Double, score: Double)] = [
            (-5, 0.1),
            (-3, 0.25),
            (-2, 0.35),
            (0, 0.5),
            (2, 0.65),
            (4, 0.8),
            (7, 0.92),
            (10, 1.0)
        ]
        return interpolatedScore(for: relativeOffset, anchors: anchors)
    }

    static func durationScore(for duration: TimeInterval) -> Double {
        let minutes = duration / 60
        let anchors: [(offset: Double, score: Double)] = [
            (5, 0.1),
            (10, 0.25),
            (20, 0.45),
            (30, 0.65),
            (45, 0.82),
            (60, 0.95)
        ]
        return interpolatedScore(for: minutes, anchors: anchors)
    }

    private static func supportingScore(for workout: Workout) -> Double? {
        var weightedValues: [(score: Double, weight: Double)] = []

        if let rating = workout.effortRating {
            weightedValues.append((((rating - 1) / 4.0), 0.45))
        }

        if let averageHeartRate = workout.avgHeartRate {
            let normalizedHeartRate = clamp((Double(averageHeartRate) - 85) / 85.0)
            weightedValues.append((normalizedHeartRate, 0.25))
        }

        if let averageMETs = workout.averageMETs {
            let normalizedMETs = clamp((averageMETs - 2) / 10.0)
            weightedValues.append((normalizedMETs, 0.15))
        }

        if let maxHeartRate = workout.maxHeartRate {
            let normalizedMaxHeartRate = clamp((Double(maxHeartRate) - 100) / 90.0)
            weightedValues.append((normalizedMaxHeartRate, 0.05))
        }

        if let totalWeight = workout.weightConfiguration?.totalWeight, totalWeight > 0 {
            weightedValues.append((clamp(totalWeight / 40.0), 0.1))
        }

        guard !weightedValues.isEmpty else { return nil }

        let totalWeight = weightedValues.reduce(0) { $0 + $1.weight }
        let totalScore = weightedValues.reduce(0) { $0 + ($1.score * $1.weight) }
        return clamp(totalScore / totalWeight)
    }

    private static func interpolatedScore(for value: Double, anchors: [(offset: Double, score: Double)]) -> Double {
        guard let firstAnchor = anchors.first, let lastAnchor = anchors.last else { return 0 }

        if value <= firstAnchor.offset {
            return firstAnchor.score
        }

        if value >= lastAnchor.offset {
            return lastAnchor.score
        }

        for (lowerAnchor, upperAnchor) in zip(anchors, anchors.dropFirst()) {
            guard value >= lowerAnchor.offset, value <= upperAnchor.offset else { continue }
            let progress = (value - lowerAnchor.offset) / (upperAnchor.offset - lowerAnchor.offset)
            return lowerAnchor.score + ((upperAnchor.score - lowerAnchor.score) * progress)
        }

        return lastAnchor.score
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
