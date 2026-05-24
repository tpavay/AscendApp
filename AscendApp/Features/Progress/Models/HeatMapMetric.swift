//
//  HeatMapMetric.swift
//  AscendApp
//
//  Heat map metric selection and scoring for the Progress calendar
//

import Foundation
import SwiftUI

/// Metrics available for heat map visualization
enum HeatMapMetric: String, CaseIterable, Identifiable {
    case effortScore = "effort_score"
    case primaryMetric = "primary_metric"
    case duration = "duration"
    case stepsPerMinute = "steps_per_minute"
    case calories = "calories"
    case avgHeartRate = "avg_heart_rate"
    case maxHeartRate = "max_heart_rate"
    case addedWeight = "added_weight"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .effortScore: return "Effort Score"
        case .primaryMetric: return "Steps"
        case .duration: return "Duration"
        case .stepsPerMinute: return "Steps/Min"
        case .calories: return "Calories"
        case .avgHeartRate: return "Avg HR"
        case .maxHeartRate: return "Max HR"
        case .addedWeight: return "Weight"
        }
    }

    var icon: String {
        switch self {
        case .effortScore: return "flame.fill"
        case .primaryMetric: return "figure.stair.stepper"
        case .duration: return "clock.fill"
        case .stepsPerMinute: return "speedometer"
        case .calories: return "bolt.fill"
        case .avgHeartRate: return "heart.fill"
        case .maxHeartRate: return "heart.fill"
        case .addedWeight: return "scalemass.fill"
        }
    }

    /// Whether this metric appears in the main stat cards
    var isInStatCards: Bool {
        switch self {
        case .effortScore, .primaryMetric, .duration, .stepsPerMinute, .calories:
            return true
        case .avgHeartRate, .maxHeartRate, .addedWeight:
            return false
        }
    }

    /// Metrics available in the "More" menu
    static var moreMetrics: [HeatMapMetric] {
        allCases.filter { !$0.isInStatCards }
    }

    /// Metrics shown in stat cards
    static var statCardMetrics: [HeatMapMetric] {
        allCases.filter { $0.isInStatCards }
    }
}

// MARK: - Heat Map Score Calculator

/// Calculates normalized scores (0.0 to 1.0) for heat map visualization
struct HeatMapScoreCalculator {

    /// Calculate score for a single workout based on the selected metric
    /// Returns a value from 0.0 to 1.0
    /// Uses stored percentile scores if available, otherwise falls back to fixed threshold calculation
    @MainActor
    static func score(for workout: Workout, metric: HeatMapMetric, using settings: SettingsManager = .shared) -> Double {
        if metric == .effortScore {
            return effortScore(for: workout, using: settings)
        }

        // First, try to use stored percentile score (snapshot from save time)
        if let storedScore = workout.percentileScore(for: metric) {
            return storedScore
        }

        // Fall back to fixed threshold calculation (for legacy workouts or if percentile not yet calculated)
        return fixedThresholdScore(for: workout, metric: metric, using: settings)
    }

    /// Calculate score using fixed thresholds (legacy method, used as fallback)
    @MainActor
    static func fixedThresholdScore(for workout: Workout, metric: HeatMapMetric, using settings: SettingsManager = .shared) -> Double {
        switch metric {
        case .effortScore:
            return effortScore(for: workout, using: settings)
        case .primaryMetric:
            return primaryMetricScore(for: workout)
        case .duration:
            return durationScore(for: workout)
        case .stepsPerMinute:
            return stepsPerMinuteScore(for: workout)
        case .calories:
            return caloriesScore(for: workout)
        case .avgHeartRate:
            return avgHeartRateScore(for: workout)
        case .maxHeartRate:
            return maxHeartRateScore(for: workout)
        case .addedWeight:
            return addedWeightScore(for: workout)
        }
    }

    /// Calculate score for multiple workouts on a day (uses highest score)
    @MainActor
    static func score(for workouts: [Workout], metric: HeatMapMetric, using settings: SettingsManager = .shared) -> Double? {
        guard !workouts.isEmpty else { return nil }
        return workouts.map { score(for: $0, metric: metric, using: settings) }.max()
    }

    /// Get the display value for a workout based on the selected metric
    @MainActor
    static func displayValue(for workout: Workout, metric: HeatMapMetric, using settings: SettingsManager = .shared) -> String {
        switch metric {
        case .effortScore:
            let score = effortScore(for: workout, using: settings)
            return (score * 10).formatted(.number.precision(.fractionLength(1))) // Display as 0.0-10.0
        case .primaryMetric:
            return "\(workout.steps)"
        case .duration:
            return workout.durationFormatted
        case .stepsPerMinute:
            if let spm = workout.stepsPerMinute {
                return spm.formatted(.number.precision(.fractionLength(0)))
            }
            return "--"
        case .calories:
            if let cal = workout.caloriesBurned {
                return "\(cal)"
            }
            return "--"
        case .avgHeartRate:
            if let hr = workout.avgHeartRate {
                return "\(hr)"
            }
            return "--"
        case .maxHeartRate:
            if let hr = workout.maxHeartRate {
                return "\(hr)"
            }
            return "--"
        case .addedWeight:
            if let weight = workout.weightConfiguration?.totalWeight, weight > 0 {
                return weight.formatted(.number.precision(.fractionLength(1)))
            }
            return "--"
        }
    }

    /// Get the unit suffix for display
    @MainActor
    static func unitSuffix(for metric: HeatMapMetric, using settings: SettingsManager = .shared) -> String {
        switch metric {
        case .effortScore: return ""
        case .primaryMetric: return " steps"
        case .duration: return ""
        case .stepsPerMinute: return " SPM"
        case .calories: return " cal"
        case .avgHeartRate, .maxHeartRate: return " BPM"
        case .addedWeight: return " lbs" // TODO: Support kg based on settings
        }
    }

    // MARK: - Individual Metric Scoring

    /// Combined effort score using multiple factors (0.0 to 1.0)
    @MainActor
    private static func effortScore(for workout: Workout, using settings: SettingsManager) -> Double {
        if let effortScoreValue = workout.effortScoreValue {
            return effortScoreValue
        }

        let baseLevel = settings.effectiveBaseLevel
        return WorkoutEffortService.analyze(
            workout: workout,
            baseLevel: baseLevel
        ).score
    }

    private static func primaryMetricScore(for workout: Workout) -> Double {
        let value = Double(workout.steps)

        let maxValue: Double = 15_000

        return min(1.0, value / maxValue)
    }

    /// Duration score
    private static func durationScore(for workout: Workout) -> Double {
        normalizedDurationScore(workout.duration)
    }

    /// Steps per minute score
    private static func stepsPerMinuteScore(for workout: Workout) -> Double {
        guard let spm = workout.stepsPerMinute else { return 0 }
        return normalizedCadenceScore(spm)
    }

    /// Calories score
    private static func caloriesScore(for workout: Workout) -> Double {
        guard let calories = workout.caloriesBurned else { return 0 }
        // Typical range: 0-100 (light), 100-300 (moderate), 300-500 (high), 500+ (very high)
        return min(1.0, Double(calories) / 600.0)
    }

    /// Average heart rate score
    private static func avgHeartRateScore(for workout: Workout) -> Double {
        guard let hr = workout.avgHeartRate else { return 0 }
        return normalizedHeartRateScore(hr)
    }

    /// Max heart rate score
    private static func maxHeartRateScore(for workout: Workout) -> Double {
        guard let hr = workout.maxHeartRate else { return 0 }
        // Max HR typically higher than avg, adjust range
        // 100-140 (low), 140-160 (moderate), 160-180 (high), 180+ (very high)
        let normalized = (Double(hr) - 100) / 100.0
        return min(1.0, max(0, normalized))
    }

    /// Added weight score
    private static func addedWeightScore(for workout: Workout) -> Double {
        guard let weight = workout.weightConfiguration?.totalWeight, weight > 0 else { return 0 }
        // Typical range: 0-10 (light), 10-25 (moderate), 25-50 (heavy), 50+ (very heavy)
        return min(1.0, weight / 60.0)
    }

    // MARK: - Normalized Score Helpers

    private static func normalizedHeartRateScore(_ avgHeartRate: Int) -> Double {
        // 80-100 (very light), 100-120 (light), 120-140 (moderate), 140-160 (hard), 160+ (very hard)
        let hr = Double(avgHeartRate)
        let normalized = (hr - 80) / 100.0
        return min(1.0, max(0, normalized))
    }

    private static func normalizedMETsScore(_ mets: Double) -> Double {
        // 2-4 (very light), 4-6 (light), 6-8 (moderate), 8-10 (hard), 10+ (very hard)
        let normalized = (mets - 2) / 10.0
        return min(1.0, max(0, normalized))
    }

    private static func normalizedCadenceScore(_ stepsPerMinute: Double) -> Double {
        let mappedLevel = SPMMappingService.level(forSPM: stepsPerMinute)
        return Double(mappedLevel - 1) / 24.0
    }

    private static func normalizedDurationScore(_ duration: TimeInterval) -> Double {
        // 0-10min (very light), 10-20 (light), 20-30 (moderate), 30-45 (hard), 45+ (very hard)
        let minutes = duration / 60.0
        let normalized = minutes / 60.0  // 60 min = 1.0
        return min(1.0, max(0, normalized))
    }
}

// MARK: - Heat Map Color Helper

extension Color {
    /// Returns a color for a given heat map score (0.0 to 1.0)
    /// Gradient: Gray (no data) -> Light Yellow -> Orange -> Deep Red
    static func heatMapColor(for score: Double, colorScheme: ColorScheme) -> Color {
        // Clamp score to valid range
        let s = min(1.0, max(0, score))

        // Color stops for smooth gradient
        // 0.0: Light yellow
        // 0.3: Yellow-orange
        // 0.6: Orange
        // 0.8: Red-orange
        // 1.0: Deep red

        if s < 0.3 {
            // Light yellow to yellow-orange
            let t = s / 0.3
            return Color(
                red: 1.0,
                green: 0.95 - (0.15 * t),
                blue: 0.7 - (0.4 * t)
            )
        } else if s < 0.6 {
            // Yellow-orange to orange
            let t = (s - 0.3) / 0.3
            return Color(
                red: 1.0,
                green: 0.8 - (0.25 * t),
                blue: 0.3 - (0.3 * t)
            )
        } else if s < 0.8 {
            // Orange to red-orange
            let t = (s - 0.6) / 0.2
            return Color(
                red: 1.0,
                green: 0.55 - (0.25 * t),
                blue: 0.0
            )
        } else {
            // Red-orange to deep red
            let t = (s - 0.8) / 0.2
            return Color(
                red: 1.0 - (0.1 * t),
                green: 0.3 - (0.3 * t),
                blue: 0.0
            )
        }
    }

    /// Returns a gradient for a given heat map score
    static func heatMapGradient(for score: Double, colorScheme: ColorScheme) -> LinearGradient {
        let baseColor = heatMapColor(for: score, colorScheme: colorScheme)
        let darkerColor = heatMapColor(for: min(1.0, score + 0.1), colorScheme: colorScheme)

        return LinearGradient(
            colors: [baseColor, darkerColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
