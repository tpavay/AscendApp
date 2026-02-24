//
//  BestEffortModels.swift
//  AscendApp
//
//  Created by GPT-5.1 on 11/20/25.
//

import Foundation

/// Derived, in-memory representation of a personal record/best effort.
struct BestEffort: Identifiable {
    enum MetricType: String, CaseIterable, Identifiable {
        case mostSteps
        case mostFloors
        case longestWorkout
        case highestStepsPerMinute
        case highestCaloriesBurned
        case highestAverageHeartRate
        case highestMaxHeartRate
        case highestAverageMETs
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .mostSteps: return "Steps"
            case .mostFloors: return "Floors"
            case .longestWorkout: return "Duration"
            case .highestStepsPerMinute: return "Steps/Min"
            case .highestCaloriesBurned: return "Calories"
            case .highestAverageHeartRate: return "Avg HR"
            case .highestMaxHeartRate: return "Max HR"
            case .highestAverageMETs: return "METs"
            }
        }
        
        var iconName: String {
            switch self {
            case .mostSteps: return "figure.stairs"
            case .mostFloors: return "building.2"
            case .longestWorkout: return "stopwatch"
            case .highestStepsPerMinute: return "speedometer"
            case .highestCaloriesBurned: return "flame.fill"
            case .highestAverageHeartRate: return "heart.fill"
            case .highestMaxHeartRate: return "bolt.heart"
            case .highestAverageMETs: return "waveform.path.ecg"
            }
        }
        
        var unitLabel: String {
            switch self {
            case .mostSteps: return "steps"
            case .mostFloors: return "floors"
            case .longestWorkout: return "min"
            case .highestStepsPerMinute: return "/min"
            case .highestCaloriesBurned: return "kcal"
            case .highestAverageHeartRate, .highestMaxHeartRate: return "bpm"
            case .highestAverageMETs: return "METs"
            }
        }
    }
    
    let id = UUID()
    let type: MetricType
    let title: String
    let valueText: String
    let detailText: String
    let date: Date
    let workout: Workout
    let iconName: String
}

/// A single data point in a best-effort progression timeline.
struct ProgressionDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let workout: Workout
}

// MARK: - Best Efforts Factory

struct BestEffortsBuilder {
    static func bestEfforts(from workouts: [Workout]) -> [BestEffort] {
        guard !workouts.isEmpty else { return [] }
        
        var results: [BestEffort] = []
        
        if let effort = mostSteps(in: workouts) {
            results.append(effort)
        }
        
        if let effort = mostFloors(in: workouts) {
            results.append(effort)
        }
        
        if let effort = longestWorkout(in: workouts) {
            results.append(effort)
        }
        
        if let effort = highestStepsPerMinute(in: workouts) {
            results.append(effort)
        }
        
        if let effort = highestCaloriesBurned(in: workouts) {
            results.append(effort)
        }
        
        if let effort = highestAverageHeartRate(in: workouts) {
            results.append(effort)
        }
        
        if let effort = highestMaxHeartRate(in: workouts) {
            results.append(effort)
        }
        
        if let effort = highestAverageMETs(in: workouts) {
            results.append(effort)
        }
        
        // Sort newest first by the workout date associated with the record
        return results.sorted { $0.date > $1.date }
    }
    
    // MARK: - Individual Metrics
    
    private static func mostSteps(in workouts: [Workout]) -> BestEffort? {
        guard let best = workouts
            .filter({ $0.steps > 0 })
            .max(by: { lhs, rhs in
                if lhs.steps == rhs.steps {
                    return lhs.date < rhs.date
                }
                return lhs.steps < rhs.steps
            }) else { return nil }
        
        return BestEffort(
            type: .mostSteps,
            title: "Most Steps in a Workout",
            valueText: formattedNumber(best.steps) + " steps",
            detailText: formattedWorkoutDetail(for: best),
            date: best.date,
            workout: best,
            iconName: "figure.stairs"
        )
    }
    
    private static func mostFloors(in workouts: [Workout]) -> BestEffort? {
        guard let best = workouts
            .filter({ $0.floors > 0 })
            .max(by: { lhs, rhs in
                if lhs.floors == rhs.floors {
                    return lhs.date < rhs.date
                }
                return lhs.floors < rhs.floors
            }) else { return nil }
        
        return BestEffort(
            type: .mostFloors,
            title: "Most Floors in a Workout",
            valueText: formattedNumber(best.floors) + " floors",
            detailText: formattedWorkoutDetail(for: best),
            date: best.date,
            workout: best,
            iconName: "building.2"
        )
    }
    
    private static func longestWorkout(in workouts: [Workout]) -> BestEffort? {
        guard let best = workouts.max(by: { $0.duration < $1.duration }) else { return nil }
        
        return BestEffort(
            type: .longestWorkout,
            title: "Longest Workout",
            valueText: formattedDuration(best.duration),
            detailText: formattedWorkoutDetail(for: best),
            date: best.date,
            workout: best,
            iconName: "stopwatch"
        )
    }
    
    private static func highestStepsPerMinute(in workouts: [Workout]) -> BestEffort? {
        guard let best = workouts
            .filter({ $0.pace(for: .steps) != nil && $0.pace(for: .steps)! > 0 })
            .max(by: { (lhs, rhs) in
                let lhsPace = lhs.pace(for: .steps) ?? 0
                let rhsPace = rhs.pace(for: .steps) ?? 0
                if lhsPace == rhsPace {
                    return lhs.date < rhs.date
                }
                return lhsPace < rhsPace
            }) else { return nil }
        
        let paceValue = best.pace(for: .steps) ?? 0
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        formatter.numberStyle = .decimal
        let paceText = formatter.string(from: NSNumber(value: paceValue)) ?? "0"
        
        return BestEffort(
            type: .highestStepsPerMinute,
            title: "Highest Steps per Minute",
            valueText: "\(paceText) / min",
            detailText: formattedWorkoutDetail(for: best),
            date: best.date,
            workout: best,
            iconName: "speedometer"
        )
    }
    
    private static func highestCaloriesBurned(in workouts: [Workout]) -> BestEffort? {
        guard let best = workouts
            .filter({ $0.caloriesBurned != nil })
            .max(by: { lhs, rhs in
                let lhsCalories = lhs.caloriesBurned ?? 0
                let rhsCalories = rhs.caloriesBurned ?? 0
                if lhsCalories == rhsCalories {
                    return lhs.date < rhs.date
                }
                return lhsCalories < rhsCalories
            }) else { return nil }
        
        let calories = best.caloriesBurned ?? 0
        return BestEffort(
            type: .highestCaloriesBurned,
            title: "Highest Calories Burned",
            valueText: formattedNumber(calories) + " kcal",
            detailText: formattedWorkoutDetail(for: best),
            date: best.date,
            workout: best,
            iconName: "flame.fill"
        )
    }
    
    private static func highestAverageHeartRate(in workouts: [Workout]) -> BestEffort? {
        guard let best = workouts
            .filter({ $0.avgHeartRate != nil })
            .max(by: { lhs, rhs in
                let lhsHR = lhs.avgHeartRate ?? 0
                let rhsHR = rhs.avgHeartRate ?? 0
                if lhsHR == rhsHR {
                    return lhs.date < rhs.date
                }
                return lhsHR < rhsHR
            }) else { return nil }
        
        let hr = best.avgHeartRate ?? 0
        return BestEffort(
            type: .highestAverageHeartRate,
            title: "Highest Average Heart Rate",
            valueText: "\(hr) bpm",
            detailText: formattedWorkoutDetail(for: best),
            date: best.date,
            workout: best,
            iconName: "heart.fill"
        )
    }
    
    private static func highestMaxHeartRate(in workouts: [Workout]) -> BestEffort? {
        guard let best = workouts
            .filter({ $0.maxHeartRate != nil })
            .max(by: { lhs, rhs in
                let lhsHR = lhs.maxHeartRate ?? 0
                let rhsHR = rhs.maxHeartRate ?? 0
                if lhsHR == rhsHR {
                    return lhs.date < rhs.date
                }
                return lhsHR < rhsHR
            }) else { return nil }
        
        let hr = best.maxHeartRate ?? 0
        return BestEffort(
            type: .highestMaxHeartRate,
            title: "Highest Max Heart Rate",
            valueText: "\(hr) bpm",
            detailText: formattedWorkoutDetail(for: best),
            date: best.date,
            workout: best,
            iconName: "bolt.heart"
        )
    }
    
    private static func highestAverageMETs(in workouts: [Workout]) -> BestEffort? {
        guard let best = workouts
            .filter({ $0.averageMETs != nil })
            .max(by: { lhs, rhs in
                let lhsMETs = lhs.averageMETs ?? 0
                let rhsMETs = rhs.averageMETs ?? 0
                if lhsMETs == rhsMETs {
                    return lhs.date < rhs.date
                }
                return lhsMETs < rhsMETs
            }) else { return nil }
        
        let mets = best.averageMETs ?? 0
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        formatter.numberStyle = .decimal
        let metsText = formatter.string(from: NSNumber(value: mets)) ?? "\(mets)"
        
        return BestEffort(
            type: .highestAverageMETs,
            title: "Highest Average METs",
            valueText: "\(metsText) METs",
            detailText: formattedWorkoutDetail(for: best),
            date: best.date,
            workout: best,
            iconName: "waveform.path.ecg"
        )
    }
    
    // MARK: - Formatting Helpers
    
    private static func formattedWorkoutDetail(for workout: Workout) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        return dateFormatter.string(from: workout.date)
    }
    
    private static func formattedNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
    
    private static func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        
        if hours > 0 {
            return "\(hours) hr \(minutes < 10 ? "0" : "")\(minutes) min"
        } else {
            return "\(minutes) min"
        }
    }
    
    // MARK: - Progression Data
    
    /// Returns all workouts that set a new record at their point in time for the given metric.
    /// Sorted by date ascending to create the "staircase" progression.
    static func progressionData(for metricType: BestEffort.MetricType, from workouts: [Workout]) -> [ProgressionDataPoint] {
        // Sort workouts by date ascending
        let sortedWorkouts = workouts.sorted { $0.date < $1.date }
        
        var progression: [ProgressionDataPoint] = []
        var currentBest: Double = 0
        
        for workout in sortedWorkouts {
            guard let value = metricValue(for: metricType, from: workout) else { continue }
            
            if value > currentBest {
                currentBest = value
                progression.append(ProgressionDataPoint(date: workout.date, value: value, workout: workout))
            }
        }
        
        return progression
    }
    
    /// Returns the available metric types that have at least one valid data point.
    static func availableMetricTypes(from workouts: [Workout]) -> [BestEffort.MetricType] {
        BestEffort.MetricType.allCases.filter { metricType in
            workouts.contains { metricValue(for: metricType, from: $0) != nil }
        }
    }
    
    /// Extracts the numeric value for a given metric type from a workout.
    private static func metricValue(for metricType: BestEffort.MetricType, from workout: Workout) -> Double? {
        switch metricType {
        case .mostSteps:
            return workout.steps > 0 ? Double(workout.steps) : nil
        case .mostFloors:
            return workout.floors > 0 ? Double(workout.floors) : nil
        case .longestWorkout:
            return workout.duration > 0 ? workout.duration / 60.0 : nil // Convert to minutes
        case .highestStepsPerMinute:
            return workout.pace(for: .steps)
        case .highestCaloriesBurned:
            return workout.caloriesBurned.map { Double($0) }
        case .highestAverageHeartRate:
            return workout.avgHeartRate.map { Double($0) }
        case .highestMaxHeartRate:
            return workout.maxHeartRate.map { Double($0) }
        case .highestAverageMETs:
            return workout.averageMETs
        }
    }
}
