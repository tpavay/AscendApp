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
    var selectedItems: [PhotosPickerItem] = []

    // Health Metrics
    var avgHeartRate: String = ""
    var maxHeartRate: String = ""
    var caloriesBurned: String = ""
    var effortRating: Double? = nil

    // UI State
    var isUploading = false
    var uploadError: String? = nil
    var durationFormatted: String = ""

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
            let workout = try await workoutService.createWorkout(from: request, with: selectedItems)

            modelContext.insert(workout)
            try modelContext.save()

            isUploading = false
            return workout

        } catch {
            isUploading = false
            uploadError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Form Processing Methods
    func formatDurationInput(_ input: String) {
        // Remove all non-digit characters
        let digits = input.filter { $0.isNumber }

        // Limit to 6 digits (hhmmss)
        let limitedDigits = String(digits.prefix(6))

        if limitedDigits.isEmpty {
            durationFormatted = ""
            durationHours = ""
            durationMinutes = ""
            durationSeconds = ""
            return
        }

        // Convert to total seconds, working from right-to-left
        var totalSeconds = 0
        let reversedDigits = Array(limitedDigits.reversed())

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
