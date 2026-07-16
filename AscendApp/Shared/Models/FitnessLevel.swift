//
//  FitnessLevel.swift
//  AscendApp
//
//  User fitness level for personalized heat map scoring thresholds.
//  Only used for first 10 workouts (bootstrap), then transitions to percentile scoring.
//

import Foundation

/// User's self-reported fitness level, used to set initial scoring thresholds
enum FitnessLevel: String, CaseIterable, Codable, Identifiable {
    case beginner
    case intermediate
    case advanced

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        }
    }

    var description: String {
        switch self {
        case .beginner:
            return "New to stair climbing or returning after a long break"
        case .intermediate:
            return "Regular stair climber with consistent workouts"
        case .advanced:
            return "Experienced climber pushing for high performance"
        }
    }

    var icon: String {
        switch self {
        case .beginner: return "figure.walk"
        case .intermediate: return "figure.stairs"
        case .advanced: return "figure.highintensity.intervaltraining"
        }
    }

    // MARK: - Threshold Values (Max values for 1.0 score)

    /// Steps threshold for max score
    var stepsThreshold: Double {
        switch self {
        case .beginner: return 6000
        case .intermediate: return 12000
        case .advanced: return 18000
        }
    }

    /// Duration threshold in seconds for max score
    var durationThreshold: Double {
        switch self {
        case .beginner: return 20 * 60      // 20 minutes
        case .intermediate: return 40 * 60  // 40 minutes
        case .advanced: return 60 * 60      // 60 minutes
        }
    }

    /// Steps per minute threshold for max score
    var stepsPerMinuteThreshold: Double {
        switch self {
        case .beginner: return 90
        case .intermediate: return 110
        case .advanced: return 130
        }
    }

    /// Calories threshold for max score
    var caloriesThreshold: Double {
        switch self {
        case .beginner: return 250
        case .intermediate: return 450
        case .advanced: return 700
        }
    }

    /// Average heart rate threshold for max score
    var avgHeartRateThreshold: Double {
        switch self {
        case .beginner: return 140
        case .intermediate: return 150
        case .advanced: return 160
        }
    }

    /// Max heart rate threshold for max score
    var maxHeartRateThreshold: Double {
        switch self {
        case .beginner: return 160
        case .intermediate: return 175
        case .advanced: return 185
        }
    }

    /// Added weight threshold in lbs for max score
    var addedWeightThreshold: Double {
        switch self {
        case .beginner: return 5       // e.g., 2.5lb ankle weights on each leg
        case .intermediate: return 20  // e.g., 20lb weighted vest
        case .advanced: return 40      // e.g., heavy vest or multiple weights
        }
    }

    /// Get threshold for a specific heat map metric
    func threshold(for metric: HeatMapMetric) -> Double {
        switch metric {
        case .effortScore:
            return 1.0  // Effort score is already 0-1 normalized
        case .primaryMetric:
            return stepsThreshold
        case .duration:
            return durationThreshold
        case .stepsPerMinute:
            return stepsPerMinuteThreshold
        case .calories:
            return caloriesThreshold
        case .avgHeartRate:
            return avgHeartRateThreshold
        case .maxHeartRate:
            return maxHeartRateThreshold
        case .addedWeight:
            return addedWeightThreshold
        }
    }
}
