//
//  WorkoutActivityAttributes.swift
//  AscendApp
//
//  Created by Claude on 2/19/26.
//

import ActivityKit
import Foundation

/// Attributes for the live workout activity
/// These define what data is shown on the lock screen and Dynamic Island
struct WorkoutActivityAttributes: ActivityAttributes {
    
    /// Static content that doesn't change during the activity
    public struct ContentState: Codable, Hashable {
        // Dynamic content that updates during workout
        var elapsedSeconds: Int
        var steps: Int
        var floors: Int
        var currentHeartRate: Int?
        var calories: Int?
        var currentSPM: Double? // Steps per minute
        
        // Formatted helpers
        var formattedDuration: String {
            let hours = elapsedSeconds / 3600
            let minutes = (elapsedSeconds % 3600) / 60
            let seconds = elapsedSeconds % 60
            
            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, seconds)
            } else {
                return String(format: "%02d:%02d", minutes, seconds)
            }
        }
        
        var formattedSteps: String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
        }
        
        var formattedSPM: String {
            guard let spm = currentSPM else { return "--" }
            return String(format: "%.0f", spm)
        }
    }
    
    // Static attributes set when activity starts
    var workoutName: String
    var startTime: Date
    var hasWeightEquipment: Bool
    var weightDescription: String? // e.g., "20lb vest"
}

// MARK: - Live Activity Manager

@MainActor
@Observable
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    
    private var currentActivity: Activity<WorkoutActivityAttributes>?
    var isActivityActive: Bool { currentActivity != nil }
    
    private init() {}
    
    // MARK: - Start Activity
    
    func startWorkoutActivity(
        workoutName: String,
        weightDescription: String? = nil
    ) {
        // Check if Live Activities are supported
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activities not enabled")
            return
        }
        
        let attributes = WorkoutActivityAttributes(
            workoutName: workoutName,
            startTime: Date(),
            hasWeightEquipment: weightDescription != nil,
            weightDescription: weightDescription
        )
        
        let initialState = WorkoutActivityAttributes.ContentState(
            elapsedSeconds: 0,
            steps: 0,
            floors: 0,
            currentHeartRate: nil,
            calories: nil,
            currentSPM: nil
        )
        
        let content = ActivityContent(state: initialState, staleDate: nil)
        
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            print("Started Live Activity: \(currentActivity?.id ?? "unknown")")
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }
    
    // MARK: - Update Activity
    
    func updateWorkoutActivity(
        elapsedSeconds: Int,
        steps: Int,
        floors: Int,
        currentHeartRate: Int? = nil,
        calories: Int? = nil,
        currentSPM: Double? = nil
    ) {
        guard let activity = currentActivity else { return }
        
        let updatedState = WorkoutActivityAttributes.ContentState(
            elapsedSeconds: elapsedSeconds,
            steps: steps,
            floors: floors,
            currentHeartRate: currentHeartRate,
            calories: calories,
            currentSPM: currentSPM
        )
        
        let content = ActivityContent(state: updatedState, staleDate: nil)
        
        Task {
            await activity.update(content)
        }
    }
    
    // MARK: - End Activity
    
    func endWorkoutActivity(
        finalSteps: Int,
        finalFloors: Int,
        finalDuration: Int
    ) {
        guard let activity = currentActivity else { return }
        
        let finalState = WorkoutActivityAttributes.ContentState(
            elapsedSeconds: finalDuration,
            steps: finalSteps,
            floors: finalFloors,
            currentHeartRate: nil,
            calories: nil,
            currentSPM: nil
        )
        
        let content = ActivityContent(state: finalState, staleDate: nil)
        
        Task {
            await activity.end(content, dismissalPolicy: .after(.now + 60)) // Show for 1 min after ending
            await MainActor.run {
                currentActivity = nil
            }
        }
    }
    
    // MARK: - Cancel Activity
    
    func cancelActivity() {
        guard let activity = currentActivity else { return }
        
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            await MainActor.run {
                currentActivity = nil
            }
        }
    }
}
