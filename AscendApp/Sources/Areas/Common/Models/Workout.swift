//
//  Workout.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import Foundation
import SwiftData

@Model
class Workout {
    var id: UUID
    var name: String
    var date: Date
    var duration: TimeInterval // Duration in seconds
    var steps: Int?
    var floors: Int?
    var notes: String
    var createdAt: Date
    var avgHeartRate: Int? // Average heart rate in BPM
    var maxHeartRate: Int? // Maximum heart rate in BPM
    var caloriesBurned: Int? // Calories burned during workout
    var effortRating: Double? // Effort rating on 1-5 scale
    
    init(name: String = "", date: Date = Date(), duration: TimeInterval, steps: Int? = nil, floors: Int? = nil, notes: String = "", avgHeartRate: Int? = nil, maxHeartRate: Int? = nil, caloriesBurned: Int? = nil, effortRating: Double? = nil) {
        self.id = UUID()
        self.name = name.isEmpty ? "Workout" : name
        self.date = date
        self.duration = duration
        self.steps = steps
        self.floors = floors
        self.notes = notes
        self.createdAt = Date()
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.caloriesBurned = caloriesBurned
        self.effortRating = effortRating
    }
    
    // Computed properties for convenience
    var durationFormatted: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    var primaryMetricValue: Int? {
        // Return the non-nil value, preferring steps if both exist
        return steps ?? floors
    }
    
    var metricType: WorkoutMetric {
        if steps != nil {
            return .steps
        } else {
            return .floors
        }
    }
    
    // Calculate pace (steps or floors per minute)
    var pace: Double? {
        guard let metricValue = primaryMetricValue, duration > 0 else { return nil }
        let minutes = duration / 60.0
        return Double(metricValue) / minutes
    }
    
    // Calculate total vertical climb using settings
    func totalVerticalClimb(stepHeight: Double, measurementSystem: MeasurementSystem) -> Double? {
        guard let steps = steps else { return nil }
        
        // Convert step height to meters first
        let stepHeightInMeters = measurementSystem.convertStepHeightToMeters(stepHeight)
        
        // Calculate total climb in meters
        let totalClimbMeters = Double(steps) * stepHeightInMeters
        
        // Convert to user's preferred distance unit
        return measurementSystem.convertMetersToDistanceUnit(totalClimbMeters)
    }
    
    // Get the appropriate unit label for vertical climb display
    func verticalClimbUnit(measurementSystem: MeasurementSystem) -> String {
        return measurementSystem.distanceAbbreviation
    }
    
    // MARK: - Streak Calculations
    static func calculateCurrentStreak(from workouts: [Workout]) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Group workouts by date
        let workoutDates = Set(workouts.map { calendar.startOfDay(for: $0.date) })
        
        var streak = 0
        var currentDate = today
        
        // Check if there's a workout today or yesterday (to handle late night logging)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        if !workoutDates.contains(today) && !workoutDates.contains(yesterday) {
            return 0
        }
        
        // Start counting from today or yesterday
        if workoutDates.contains(today) {
            currentDate = today
        } else if workoutDates.contains(yesterday) {
            currentDate = yesterday
        }
        
        // Count consecutive days backward
        while workoutDates.contains(currentDate) {
            streak += 1
            currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate)!
        }
        
        return streak
    }
    
    static func getWeeklyActivity(from workouts: [Workout], for date: Date = Date()) -> [Date: Bool] {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        
        // Get all 7 days of the current week
        var weekDates: [Date] = []
        for i in 0..<7 {
            if let day = calendar.date(byAdding: .day, value: i, to: startOfWeek) {
                weekDates.append(calendar.startOfDay(for: day))
            }
        }
        
        // Group workouts by date
        let workoutDates = Set(workouts.map { calendar.startOfDay(for: $0.date) })
        
        // Create dictionary mapping dates to workout completion
        var weekActivity: [Date: Bool] = [:]
        for date in weekDates {
            weekActivity[date] = workoutDates.contains(date)
        }
        
        return weekActivity
    }
}