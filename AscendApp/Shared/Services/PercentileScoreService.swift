//
//  PercentileScoreService.swift
//  AscendApp
//
//  Service for calculating percentile-based heat map scores.
//  Uses snapshot percentile scoring where scores are calculated once at save time
//  and stored permanently on the workout.
//

import Foundation

/// Service for calculating percentile-based heat map scores
@MainActor
struct PercentileScoreService {

    // MARK: - Percentile Calculation

    /// Calculate the percentile rank of a value against historical values
    /// Uses: percentile = (countBelow + 0.5 * countEqual) / totalCount
    /// Returns a value from 0.0 to 1.0
    static func calculatePercentileRank(value: Double, historicalValues: [Double]) -> Double {
        guard !historicalValues.isEmpty else { return 0.5 }

        var countBelow = 0
        var countEqual = 0

        for historicalValue in historicalValues {
            if historicalValue < value {
                countBelow += 1
            } else if abs(historicalValue - value) < 0.0001 {
                countEqual += 1
            }
        }

        let totalCount = historicalValues.count
        return (Double(countBelow) + 0.5 * Double(countEqual)) / Double(totalCount)
    }

    // MARK: - Score Calculation with Hybrid Blending

    /// Calculate the final heat map score using hybrid blending
    /// - For 0-10 workouts: 100% fixed threshold scoring
    /// - For 10-20 workouts: Linear blend between fixed and percentile
    /// - For 20+ workouts: 100% percentile scoring
    static func calculateHybridScore(
        percentileScore: Double,
        fixedScore: Double,
        workoutCount: Int
    ) -> Double {
        // Calculate blend ratio: 0 at 10 workouts, 1 at 20 workouts
        let blendRatio = max(0, min(1, Double(workoutCount - 10) / 10.0))

        return (1 - blendRatio) * fixedScore + blendRatio * percentileScore
    }

    // MARK: - All Metric Percentile Calculation

    /// Calculate percentile scores for all heat map metrics for a workout
    /// Should be called at workout save time
    static func calculateAllPercentiles(
        for workout: Workout,
        existingWorkouts: [Workout],
        preferredMetric: WorkoutMetric
    ) -> [String: Double] {
        // Only consider workouts BEFORE this workout for percentile calculation
        let historicalWorkouts = existingWorkouts.filter { $0.date < workout.date }
        let workoutCount = historicalWorkouts.count
        let workoutValues = metricValues(for: workout, preferredMetric: preferredMetric)
        let historicalValuesByMetric = historicalValuesByMetric(
            from: historicalWorkouts,
            preferredMetric: preferredMetric
        )

        var scores: [String: Double] = [:]
        scores.reserveCapacity(HeatMapMetric.allCases.count)

        for metric in HeatMapMetric.allCases {
            let score = calculateScore(
                metric: metric,
                value: workoutValues[metric],
                historicalValues: historicalValuesByMetric[metric] ?? [],
                workoutCount: workoutCount,
                preferredMetric: preferredMetric
            )
            scores[metric.rawValue] = score
        }

        return scores
    }

    /// Calculate the score for a single metric
    private static func calculateScore(
        metric: HeatMapMetric,
        value: Double?,
        historicalValues: [Double],
        workoutCount: Int,
        preferredMetric: WorkoutMetric
    ) -> Double {
        // If no value (e.g., no heart rate data), return 0
        guard let value = value else { return 0 }

        if metric == .effortScore {
            guard !historicalValues.isEmpty else { return 0.5 }
            return calculatePercentileRank(value: value, historicalValues: historicalValues)
        }

        let fixedScore = fixedScore(
            metric: metric,
            value: value,
            preferredMetric: preferredMetric
        )

        // If not enough workouts for percentile, use fixed score
        if workoutCount < 10 {
            return fixedScore
        }

        // If no historical data for this metric, use fixed score
        guard !historicalValues.isEmpty else { return fixedScore }

        // Calculate percentile score
        let percentileScore = calculatePercentileRank(value: value, historicalValues: historicalValues)

        // Apply hybrid blending
        return calculateHybridScore(
            percentileScore: percentileScore,
            fixedScore: fixedScore,
            workoutCount: workoutCount
        )
    }

    private static func historicalValuesByMetric(
        from workouts: [Workout],
        preferredMetric: WorkoutMetric
    ) -> [HeatMapMetric: [Double]] {
        workouts.reduce(into: [:]) { result, workout in
            for (metric, value) in metricValues(for: workout, preferredMetric: preferredMetric) {
                result[metric, default: []].append(value)
            }
        }
    }

    private static func metricValues(
        for workout: Workout,
        preferredMetric: WorkoutMetric
    ) -> [HeatMapMetric: Double] {
        HeatMapMetric.allCases.reduce(into: [:]) { result, metric in
            guard let value = getRawValue(for: workout, metric: metric, preferredMetric: preferredMetric) else {
                return
            }
            result[metric] = value
        }
    }

    // MARK: - Raw Value Extraction

    /// Get the raw value for a workout metric
    private static func getRawValue(
        for workout: Workout,
        metric: HeatMapMetric,
        preferredMetric: WorkoutMetric
    ) -> Double? {
        switch metric {
        case .effortScore:
            // For effort score, we use the calculated effort value
            return calculateEffortValue(for: workout)
        case .primaryMetric:
            return Double(preferredMetric == .steps ? workout.steps : workout.floors)
        case .duration:
            return workout.duration
        case .stepsPerMinute:
            return workout.stepsPerMinute
        case .calories:
            if let cal = workout.caloriesBurned {
                return Double(cal)
            }
            return nil
        case .avgHeartRate:
            if let hr = workout.avgHeartRate {
                return Double(hr)
            }
            return nil
        case .maxHeartRate:
            if let hr = workout.maxHeartRate {
                return Double(hr)
            }
            return nil
        case .addedWeight:
            if let weight = workout.weightConfiguration?.totalWeight, weight > 0 {
                return weight
            }
            return nil
        }
    }

    /// Calculate the effort value for a workout (used as input for percentile calculation)
    private static func calculateEffortValue(for workout: Workout) -> Double {
        if let effortScoreValue = workout.effortScoreValue {
            return effortScoreValue
        }

        let baseLevel = SettingsManager.shared.effectiveBaseLevel
        return WorkoutEffortService.analyze(
            workout: workout,
            baseLevel: baseLevel
        ).score
    }

    private static func fixedScore(
        metric: HeatMapMetric,
        value: Double,
        preferredMetric: WorkoutMetric
    ) -> Double {
        let maxValue: Double
        switch metric {
        case .effortScore:
            return value
        case .primaryMetric:
            maxValue = preferredMetric == .steps ? 15_000 : 150
        case .duration:
            maxValue = 3_600
        case .stepsPerMinute:
            return min(1.0, max(0, Double(SPMMappingService.level(forSPM: value) - 1) / 24.0))
        case .calories:
            maxValue = 600
        case .avgHeartRate:
            maxValue = 180
            return min(1.0, max(0, (value - 80) / (maxValue - 80)))
        case .maxHeartRate:
            maxValue = 190
            return min(1.0, max(0, (value - 100) / (maxValue - 100)))
        case .addedWeight:
            maxValue = 60
        }

        return min(1.0, max(0, value / maxValue))
    }
}
