//
//  WorkoutIntensityCalculator.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/20/25.
//

import Foundation

enum WorkoutIntensity: String, CaseIterable, Codable {
    case veryLight = "very_light"
    case light = "light"
    case moderate = "moderate"
    case hard = "hard"
    case veryHard = "very_hard"
    
    var displayName: String {
        switch self {
        case .veryLight: return "Very Light"
        case .light: return "Light"
        case .moderate: return "Moderate"
        case .hard: return "Hard"
        case .veryHard: return "Very Hard"
        }
    }
    
    var description: String {
        switch self {
        case .veryLight:
            return "Slow, casual climbing pace - warming up or cooling down"
        case .light:
            return "Steady climbing pace you could maintain for hours"
        case .moderate:
            return "Comfortable climbing where conversation is still possible"
        case .hard:
            return "Challenging climb that requires focus and pushing yourself"
        case .veryHard:
            return "Maximum climbing effort - sprinting up the stairs"
        }
    }
    
    /// Returns a normalized value from 0.0 to 1.0
    var normalizedValue: Double {
        switch self {
        case .veryLight: return 0.1
        case .light: return 0.3
        case .moderate: return 0.5
        case .hard: return 0.75
        case .veryHard: return 1.0
        }
    }
}

/// Calculates workout intensity based on multiple factors
struct WorkoutIntensityCalculator {
    
    /// Main method to calculate workout intensity
    /// Priority order:
    /// 1. User entered effort rating (if manually added)
    /// 2. Heart rate data (most indicative of intensity)
    /// 3. Apple Health METs + Steps/Duration
    /// 4. Fallback to Steps + Duration (always present)
    static func calculateIntensity(for workout: Workout) -> WorkoutIntensity {
        // Priority 1: User entered effort rating (1-5 scale)
        if let effortRating = workout.effortRating {
            return intensityFromEffortRating(effortRating)
        }
        
        // Priority 2: Heart rate based calculation
        if let avgHeartRate = workout.avgHeartRate {
            let heartRateScore = normalizedHeartRateScore(avgHeartRate)
            
            // Factor in METs if available (but weighted less than heart rate)
            if let averageMETs = workout.averageMETs {
                let metsScore = normalizedMETsScore(averageMETs)
                let combinedScore = (heartRateScore * 0.7) + (metsScore * 0.3)
                return intensityFromNormalizedScore(combinedScore)
            }
            
            // Factor in steps per minute if available
            if let stepsPerMinute = workout.stepsPerMinute {
                let cadenceScore = normalizedCadenceScore(stepsPerMinute)
                let combinedScore = (heartRateScore * 0.8) + (cadenceScore * 0.2)
                return intensityFromNormalizedScore(combinedScore)
            }
            
            return intensityFromNormalizedScore(heartRateScore)
        }
        
        // Priority 3: METs-based calculation (Apple Health intensity)
        if let averageMETs = workout.averageMETs {
            let metsScore = normalizedMETsScore(averageMETs)
            
            // Enhance with cadence if available
            if let stepsPerMinute = workout.stepsPerMinute {
                let cadenceScore = normalizedCadenceScore(stepsPerMinute)
                let combinedScore = (metsScore * 0.6) + (cadenceScore * 0.4)
                return intensityFromNormalizedScore(combinedScore)
            }
            
            return intensityFromNormalizedScore(metsScore)
        }
        
        // Priority 4: Fallback to steps and duration (manual logs without HR)
        if let stepsPerMinute = workout.stepsPerMinute {
            let cadenceScore = normalizedCadenceScore(stepsPerMinute)
            let durationScore = normalizedDurationScore(workout.duration)
            
            // Weight cadence more heavily than duration
            let combinedScore = (cadenceScore * 0.7) + (durationScore * 0.3)
            return intensityFromNormalizedScore(combinedScore)
        }
        
        // Final fallback: just use duration
        let durationScore = normalizedDurationScore(workout.duration)
        return intensityFromNormalizedScore(durationScore)
    }
    
    // MARK: - Effort Rating Conversion
    
    private static func intensityFromEffortRating(_ rating: Double) -> WorkoutIntensity {
        switch rating {
        case 0..<1.5:
            return .veryLight
        case 1.5..<2.5:
            return .light
        case 2.5..<3.5:
            return .moderate
        case 3.5..<4.5:
            return .hard
        default:
            return .veryHard
        }
    }
    
    // MARK: - Normalized Score Conversion
    
    private static func intensityFromNormalizedScore(_ score: Double) -> WorkoutIntensity {
        switch score {
        case 0..<0.2:
            return .veryLight
        case 0.2..<0.4:
            return .light
        case 0.4..<0.6:
            return .moderate
        case 0.6..<0.8:
            return .hard
        default:
            return .veryHard
        }
    }
    
    // MARK: - Heart Rate Scoring
    
    /// Normalize heart rate to 0-1 scale
    /// Assumes:
    /// - < 100 bpm = very light
    /// - 100-120 = light
    /// - 120-140 = moderate
    /// - 140-160 = hard
    /// - > 160 = very hard
    private static func normalizedHeartRateScore(_ avgHeartRate: Int) -> Double {
        let hr = Double(avgHeartRate)
        
        switch hr {
        case 0..<100:
            return 0.1
        case 100..<120:
            return 0.3
        case 120..<140:
            return 0.5
        case 140..<160:
            return 0.75
        default:
            return 1.0
        }
    }
    
    // MARK: - METs Scoring
    
    /// Normalize METs to 0-1 scale
    /// METs (Metabolic Equivalent of Task):
    /// - < 3 = very light
    /// - 3-6 = light to moderate
    /// - 6-9 = moderate to hard
    /// - > 9 = very hard
    private static func normalizedMETsScore(_ mets: Double) -> Double {
        switch mets {
        case 0..<3:
            return 0.15
        case 3..<6:
            return 0.35
        case 6..<9:
            return 0.65
        case 9..<12:
            return 0.85
        default:
            return 1.0
        }
    }
    
    // MARK: - Cadence Scoring
    
    /// Normalize steps per minute to 0-1 scale
    /// Typical stair climbing cadence:
    /// - < 60 spm = very light
    /// - 60-80 = light
    /// - 80-100 = moderate
    /// - 100-120 = hard
    /// - > 120 = very hard
    private static func normalizedCadenceScore(_ stepsPerMinute: Double) -> Double {
        switch stepsPerMinute {
        case 0..<60:
            return 0.15
        case 60..<80:
            return 0.35
        case 80..<100:
            return 0.55
        case 100..<120:
            return 0.75
        default:
            return 0.95
        }
    }
    
    // MARK: - Duration Scoring
    
    /// Normalize duration to 0-1 scale
    /// Longer workouts tend to be more intense overall
    /// - < 10 min = very light
    /// - 10-20 min = light
    /// - 20-30 min = moderate
    /// - 30-45 min = hard
    /// - > 45 min = very hard
    private static func normalizedDurationScore(_ duration: TimeInterval) -> Double {
        let minutes = duration / 60.0
        
        switch minutes {
        case 0..<10:
            return 0.2
        case 10..<20:
            return 0.35
        case 20..<30:
            return 0.5
        case 30..<45:
            return 0.7
        default:
            return 0.85
        }
    }
}

// MARK: - Workout Extension

extension Workout {
    /// Computed property for workout intensity
    var intensity: WorkoutIntensity {
        WorkoutIntensityCalculator.calculateIntensity(for: self)
    }
    
    /// Steps per minute helper
    var stepsPerMinute: Double? {
        guard steps > 0, duration > 0 else { return nil }
        return Double(steps) / (duration / 60.0)
    }
}

