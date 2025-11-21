//
//  WorkoutFormViewModel.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/21/25.
//

import Foundation
import PhotosUI
import SwiftUI
import SwiftData

@MainActor
@Observable
class WorkoutFormViewModel {
    // MARK: - Form State
    var workoutName: String = ""
    var workoutDate = Date()
    var durationHours: String = ""
    var durationMinutes: String = ""
    var durationSeconds: String = ""
    var metricValue: String = ""
    var notes: String = ""
    var selectedImages: [SelectedPhotoItem] = []

    // Health Metrics
    var avgHeartRate: String = ""
    var maxHeartRate: String = ""
    var caloriesBurned: String = ""
    var effortRating: Double? = nil

    // UI State
    var isUploading = false
    var uploadError: String? = nil
    var durationFormatted: String = ""
    private var rawDurationDigits: String = ""

    // Dependencies
    private let workoutService: WorkoutService
    private let settingsManager: SettingsManager

    init(
        workoutService: WorkoutService = WorkoutService(),
        settingsManager: SettingsManager = SettingsManager.shared
    ) {
        self.workoutService = workoutService
        self.settingsManager = settingsManager

        // Set default workout name
        if workoutName.isEmpty {
            workoutName = generateDefaultWorkoutName()
        }
    }

    // MARK: - Computed Properties
    var isFormValid: Bool {
        let basicValidation = !workoutName.isEmpty &&
        workoutName.count <= 50 &&
        !durationMinutes.isEmpty &&
        !durationSeconds.isEmpty &&
        !metricValue.isEmpty &&
        Int(durationMinutes) != nil &&
        Int(durationSeconds) != nil &&
        Int(metricValue) != nil &&
        (Int(durationMinutes) ?? 0) < 60 &&
        (Int(durationSeconds) ?? 0) < 60 &&
        (durationHours.isEmpty || (Int(durationHours) != nil && (Int(durationHours) ?? 0) <= 999))

        // Validate duration is greater than 0
        let hours = Int(durationHours) ?? 0
        let minutes = Int(durationMinutes) ?? 0
        let seconds = Int(durationSeconds) ?? 0
        let totalDurationSeconds = hours * 3600 + minutes * 60 + seconds
        let durationValid = totalDurationSeconds > 0

        // Validate health metrics if provided
        let avgHRValid = avgHeartRate.isEmpty || (Int(avgHeartRate) != nil && (Int(avgHeartRate) ?? 0) >= 25 && (Int(avgHeartRate) ?? 0) <= 230)
        let maxHRValid = maxHeartRate.isEmpty || (Int(maxHeartRate) != nil && (Int(maxHeartRate) ?? 0) >= 25 && (Int(maxHeartRate) ?? 0) <= 230)
        let caloriesValid = caloriesBurned.isEmpty || (Int(caloriesBurned) != nil && (Int(caloriesBurned) ?? 0) >= 0)

        return basicValidation && durationValid && avgHRValid && maxHRValid && caloriesValid && !isUploading
    }

    // MARK: - Actions
    func saveWorkout(to modelContext: ModelContext) async throws -> Workout {
        guard isFormValid else {
            throw WorkoutFormError.invalidForm
        }

        isUploading = true
        uploadError = nil

        do {
            let request = try createWorkoutRequest()

            // Convert SelectedPhotoItem to PhotosPickerItem for the service
            let pickerItems = selectedImages.map { $0.pickerItem }
            let workout = try await workoutService.createWorkout(from: request, with: pickerItems)

            modelContext.insert(workout)
            try modelContext.save()
            
            // Check for personal records after the workout is saved
            let prResults = try checkAndSavePersonalRecords(
                for: workout,
                modelContext: modelContext
            )
            
            // Update workout with PR types if any were achieved
            if !prResults.isEmpty {
                let prTypes = prResults.map { $0.type.rawValue }
                workout.personalRecordTypes = prTypes
                try modelContext.save()
            }

            isUploading = false
            return workout

        } catch {
            isUploading = false
            uploadError = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Personal Records
    private func checkAndSavePersonalRecords(
        for workout: Workout,
        modelContext: ModelContext
    ) throws -> [PersonalRecordResult] {
        // Fetch all current personal records
        let allRecords = try PersonalRecordService.fetchCurrentPersonalRecords(
            modelContext: modelContext
        )
        
        // Check for PRs in this workout
        let prResults = PersonalRecordService.checkForPersonalRecords(
            workout: workout,
            allPersonalRecords: allRecords,
            measurementSystem: settingsManager.measurementSystem,
            stepHeight: settingsManager.stepHeight
        )
        
        // Filter to only new records
        let newRecords = prResults.filter { $0.isNewRecord }
        
        // Save the new personal records
        if !newRecords.isEmpty {
            try PersonalRecordService.savePersonalRecords(
                results: newRecords,
                workout: workout,
                modelContext: modelContext
            )
        }
        
        return newRecords
    }

    // MARK: - Form Processing Methods
    func formatDurationInput(_ newValue: String, oldValue: String) {
        let previousDigits = oldValue.filter { $0.isNumber }
        let incomingDigits = newValue.filter { $0.isNumber }

        // Clear everything if the user deletes all input
        if incomingDigits.isEmpty {
            rawDurationDigits = ""
            durationFormatted = ""
            durationHours = ""
            durationMinutes = ""
            durationSeconds = ""
            return
        }

        // Update the raw digit buffer based on the change in digit count
        if incomingDigits.count > previousDigits.count {
            // Append only the newly typed digits
            let addedCount = incomingDigits.count - previousDigits.count
            let addedDigits = incomingDigits.suffix(addedCount)
            rawDurationDigits.append(contentsOf: addedDigits)
        } else if incomingDigits.count < previousDigits.count {
            // Remove digits from the end when the user backspaces
            let removedCount = previousDigits.count - incomingDigits.count
            if removedCount >= rawDurationDigits.count {
                rawDurationDigits = ""
            } else {
                rawDurationDigits = String(rawDurationDigits.dropLast(removedCount))
            }
        } else {
            // Same count usually means paste/replace; sync to the incoming digits
            rawDurationDigits = incomingDigits
        }

        // Limit to 6 digits (hhmmss)
        rawDurationDigits = String(rawDurationDigits.prefix(6))

        // Convert to total seconds, working from right-to-left
        var totalSeconds = 0
        let reversedDigits = Array(rawDurationDigits.reversed())

        // Process digits as seconds, then minutes, then hours
        for (index, digit) in reversedDigits.enumerated() {
            if let digitValue = Int(String(digit)) {
                switch index {
                case 0: // ones place of seconds
                    totalSeconds += digitValue
                case 1: // tens place of seconds
                    totalSeconds += digitValue * 10
                case 2: // ones place of minutes
                    totalSeconds += digitValue * 60
                case 3: // tens place of minutes
                    totalSeconds += digitValue * 600
                case 4: // ones place of hours
                    totalSeconds += digitValue * 3600
                case 5: // tens place of hours
                    totalSeconds += digitValue * 36000
                default:
                    break
                }
            }
        }

        // Convert back to hours, minutes, seconds
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        // Format display based on whether hours is non-zero
        if hours == 0 {
            // Show as MM:SS
            durationFormatted = String(format: "%02d:%02d", minutes, seconds)
        } else {
            // Show as H:MM:SS
            durationFormatted = String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        // Update individual components for saving
        durationHours = String(format: "%02d", hours)
        durationMinutes = String(format: "%02d", minutes)
        durationSeconds = String(format: "%02d", seconds)
    }

    func setDuration(hours: Int, minutes: Int, seconds: Int) {
        let clampedHours = min(max(hours, 0), 999)
        let clampedMinutes = min(max(minutes, 0), 59)
        let clampedSeconds = min(max(seconds, 0), 59)

        let hasHours = clampedHours > 0
        durationHours = String(format: "%02d", clampedHours)
        durationMinutes = String(format: "%02d", clampedMinutes)
        durationSeconds = String(format: "%02d", clampedSeconds)

        if hasHours {
            durationFormatted = String(format: "%d:%02d:%02d", clampedHours, clampedMinutes, clampedSeconds)
        } else {
            durationFormatted = String(format: "%02d:%02d", clampedMinutes, clampedSeconds)
        }

        let hoursDigits = hasHours ? String(clampedHours) : ""
        rawDurationDigits = hoursDigits + String(format: "%02d%02d", clampedMinutes, clampedSeconds)
    }

    func validateHeartRateOnSubmit(_ value: String) -> String {
        let digits = value.filter { $0.isNumber }
        if digits.isEmpty { return "" }

        guard let intValue = Int(digits) else { return value }

        if intValue < 25 {
            return "25"
        } else if intValue > 230 {
            return "230"
        } else {
            return String(intValue)
        }
    }

    func validateCaloriesOnSubmit(_ value: String) -> String {
        let digits = value.filter { $0.isNumber }
        if digits.isEmpty { return "" }

        guard let intValue = Int(digits) else { return value }
        return intValue < 0 ? "0" : String(intValue)
    }

    func filterNumericInput(_ input: String) -> String {
        return input.filter { $0.isNumber }
    }

    func formatWorkoutDateTime() -> String {
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"

        if calendar.isDateInToday(workoutDate) {
            return "Today at \(timeFormatter.string(from: workoutDate))"
        } else if calendar.isDateInYesterday(workoutDate) {
            return "Yesterday at \(timeFormatter.string(from: workoutDate))"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"
            return "\(dateFormatter.string(from: workoutDate)) at \(timeFormatter.string(from: workoutDate))"
        }
    }

    func effortRatingDisplayText() -> String {
        guard let rating = effortRating else {
            return "Add effort rating (optional)"
        }

        let ratingInt = Int(rating)
        let description = effortDescription(for: rating)
        return "Effort: \(ratingInt)/5 - \(description)"
    }

    // MARK: - Helper Methods
    private func createWorkoutRequest() throws -> CreateWorkoutRequest {
        guard let minutes = Int(durationMinutes),
              let seconds = Int(durationSeconds),
              let value = Int(metricValue) else {
            throw WorkoutFormError.invalidInput
        }

        let hours = Int(durationHours) ?? 0
        let totalDuration = TimeInterval(hours * 3600 + minutes * 60 + seconds)

        let avgHR = !avgHeartRate.isEmpty ? Int(avgHeartRate) : nil
        let maxHR = !maxHeartRate.isEmpty ? Int(maxHeartRate) : nil
        let calories = !caloriesBurned.isEmpty ? Int(caloriesBurned) : nil

        return CreateWorkoutRequest(
            name: workoutName.isEmpty ? generateDefaultWorkoutName() : workoutName,
            date: workoutDate,
            duration: totalDuration,
            steps: settingsManager.preferredWorkoutMetric == .steps ? value : nil,
            floors: settingsManager.preferredWorkoutMetric == .floors ? value : nil,
            notes: notes,
            avgHeartRate: avgHR,
            maxHeartRate: maxHR,
            caloriesBurned: calories,
            effortRating: effortRating
        )
    }

    private func generateDefaultWorkoutName() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Morning Workout"
        case 12..<18: return "Afternoon Workout"
        default: return "Evening Workout"
        }
    }

    private func effortDescription(for rating: Double) -> String {
        switch Int(rating) {
        case 1: return "Minimal"
        case 2: return "Light"
        case 3: return "Moderate"
        case 4: return "High"
        case 5: return "Maximum"
        default: return "Moderate"
        }
    }
}

enum WorkoutFormError: LocalizedError {
    case invalidForm
    case invalidInput

    var errorDescription: String? {
        switch self {
        case .invalidForm: return "Please fill in all required fields"
        case .invalidInput: return "Invalid input values"
        }
    }
}
