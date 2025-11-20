//
//  BestEffortModels.swift
//  AscendApp
//
//  Created by GPT-5.1 on 11/20/25.
//

import Foundation

/// Derived, in-memory representation of a personal record/best effort.
struct BestEffort: Identifiable {
    enum MetricType: String {
        case mostSteps
        case mostFloors
        case longestWorkout
        case highestStepsPerMinute
        case highestCaloriesBurned
        case highestAverageHeartRate
        case highestMaxHeartRate
        case highestAverageMETs
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
            .filter({ $0.steps != nil })
            .max(by: { lhs, rhs in
                let lhsSteps = lhs.steps ?? 0
                let rhsSteps = rhs.steps ?? 0
                if lhsSteps == rhsSteps {
                    return lhs.date < rhs.date
                }
                return lhsSteps < rhsSteps
            }) else { return nil }
        
        let steps = best.steps ?? 0
        return BestEffort(
            type: .mostSteps,
            title: "Most Steps in a Workout",
            valueText: formattedNumber(steps) + " steps",
            detailText: formattedWorkoutDetail(for: best),
            date: best.date,
            workout: best,
            iconName: "figure.walk"
        )
    }
    
    private static func mostFloors(in workouts: [Workout]) -> BestEffort? {
        guard let best = workouts
            .filter({ $0.floors != nil })
            .max(by: { lhs, rhs in
                let lhsFloors = lhs.floors ?? 0
                let rhsFloors = rhs.floors ?? 0
                if lhsFloors == rhsFloors {
                    return lhs.date < rhs.date
                }
                return lhsFloors < rhsFloors
            }) else { return nil }
        
        let floors = best.floors ?? 0
        return BestEffort(
            type: .mostFloors,
            title: "Most Floors in a Workout",
            valueText: formattedNumber(floors) + " floors",
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
            .filter({ $0.pace != nil })
            .max(by: { (lhs, rhs) in
                let lhsPace = lhs.pace ?? 0
                let rhsPace = rhs.pace ?? 0
                if lhsPace == rhsPace {
                    return lhs.date < rhs.date
                }
                return lhsPace < rhsPace
            }) else { return nil }
        
        let paceValue = best.pace ?? 0
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
            return String(format: "%d hr %02d min", hours, minutes)
        } else {
            return String(format: "%d min", minutes)
        }
    }
}
