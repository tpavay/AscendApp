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
struct PercentileScoreService {

    // MARK: - Percentile Calculation

    /// Calculate the percentile rank of a value against historical values
    /// Uses: percentile = (countBelow + 0.5 * countEqual) / totalCount
    /// Returns a value from 0.0 to 1.0
    static func calculatePercentileRank(value: Double, historicalValues: [Double]) -> Double {
        guard !historicalValues.isEmpty else { return 0.5 }

        let countBelow = historicalValues.filter { $0 < value }.count
        let countEqual = historicalValues.filter { abs($0 - value) < 0.0001 }.count
        let totalCount = historicalValues.count

        return (Double(countBelow) + 0.5 * Double(countEqual)) / Double(totalCount)
    }

    // MARK: - Score Calculation with Hybrid Blending

    /// Calculate the final heat map score using hybrid blending
    /// - For 0-10 workouts: 100% fixed threshold scoring
    /// - For 10-20 workouts: Linear blend between fixed and percentile
    /// - For 20+ workouts: 100% percentile scoring
    @MainActor
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
    @MainActor
    static func calculateAllPercentiles(
        for workout: Workout,
        existingWorkouts: [Workout],
        fitnessLevel: FitnessLevel,
        preferredMetric: WorkoutMetric
    ) -> [String: Double] {
        // Only consider workouts BEFORE this workout for percentile calculation
        let historicalWorkouts = existingWorkouts.filter { $0.date < workout.date }
        let workoutCount = historicalWorkouts.count

        var scores: [String: Double] = [:]

        for metric in HeatMapMetric.allCases {
            let score = calculateScore(
                for: workout,
                metric: metric,
                historicalWorkouts: historicalWorkouts,
                workoutCount: workoutCount,
                fitnessLevel: fitnessLevel,
                preferredMetric: preferredMetric
            )
            scores[metric.rawValue] = score
        }

        return scores
    }

    /// Calculate the score for a single metric
    @MainActor
    private static func calculateScore(
        for workout: Workout,
        metric: HeatMapMetric,
        historicalWorkouts: [Workout],
        workoutCount: Int,
        fitnessLevel: FitnessLevel,
        preferredMetric: WorkoutMetric
    ) -> Double {
        let rawValue = getRawValue(for: workout, metric: metric, preferredMetric: preferredMetric)

        // If no value (e.g., no heart rate data), return 0
        guard let value = rawValue else { return 0 }

        // Calculate fixed threshold score
        let threshold = fitnessLevel.threshold(for: metric, preferredMetric: preferredMetric)
        let fixedScore = min(1.0, value / threshold)

        // If not enough workouts for percentile, use fixed score
        if workoutCount < 10 {
            return fixedScore
        }

        // Get historical values for this metric
        let historicalValues = historicalWorkouts.compactMap { workout in
            getRawValue(for: workout, metric: metric, preferredMetric: preferredMetric)
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

    // MARK: - Raw Value Extraction

    /// Get the raw value for a workout metric
    @MainActor
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
    /// This is a composite score based on multiple factors
    private static func calculateEffortValue(for workout: Workout) -> Double {
        var scores: [(value: Double, weight: Double)] = []

        // Priority 1: User effort rating (if set) - highest weight
        if let rating = workout.effortRating {
            let normalized = (rating - 1) / 4.0
            scores.append((normalized, 0.4))
        }

        // Priority 2: Heart rate data
        if let avgHR = workout.avgHeartRate {
            let hrScore = normalizedHeartRateScore(avgHR)
            scores.append((hrScore, 0.3))
        }

        // Priority 3: METs from Apple Health
        if let mets = workout.averageMETs {
            let metsScore = normalizedMETsScore(mets)
            scores.append((metsScore, 0.2))
        }

        // Priority 4: Cadence (steps per minute)
        if let spm = workout.stepsPerMinute {
            let cadenceScore = normalizedCadenceScore(spm)
            scores.append((cadenceScore, 0.15))
        }

        // Priority 5: Duration (longer = more effort)
        let durationScore = normalizedDurationScore(workout.duration)
        scores.append((durationScore, 0.1))

        // If no data, use duration only
        if scores.isEmpty {
            return durationScore
        }

        // Weighted average
        let totalWeight = scores.reduce(0) { $0 + $1.weight }
        let weightedSum = scores.reduce(0) { $0 + ($1.value * $1.weight) }

        return min(1.0, weightedSum / totalWeight)
    }

    // MARK: - Normalized Score Helpers

    private static func normalizedHeartRateScore(_ avgHeartRate: Int) -> Double {
        let hr = Double(avgHeartRate)
        let normalized = (hr - 80) / 100.0
        return min(1.0, max(0, normalized))
    }

    private static func normalizedMETsScore(_ mets: Double) -> Double {
        let normalized = (mets - 2) / 10.0
        return min(1.0, max(0, normalized))
    }

    private static func normalizedCadenceScore(_ stepsPerMinute: Double) -> Double {
        let normalized = (stepsPerMinute - 40) / 100.0
        return min(1.0, max(0, normalized))
    }

    private static func normalizedDurationScore(_ duration: TimeInterval) -> Double {
        let minutes = duration / 60.0
        let normalized = minutes / 60.0
        return min(1.0, max(0, normalized))
    }
}
