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
    var highlightedSelectedItemId: UUID?
    var selectedImages: [SelectedPhotoItem] = [] {
        didSet {
            if let highlightedId = highlightedSelectedItemId,
               !selectedImages.contains(where: { $0.id == highlightedId }) {
                highlightedSelectedItemId = nil
            }
            
            if highlightedSelectedItemId == nil {
                highlightedSelectedItemId = selectedImages.first?.id
            }
        }
    }

    // Health Metrics
    var avgHeartRate: String = ""
    var maxHeartRate: String = ""
    var caloriesBurned: String = ""
    var effortRating: Double? = nil

    // Weight Equipment
    var weightConfiguration: WeightConfiguration = .empty

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

        // Set default workout name based on workout date
        if workoutName.isEmpty {
            workoutName = Workout.generateDefaultName(for: workoutDate)
        }
    }

    // MARK: - Prefill from Console Scan

    /// Prefill form fields from a console scan result
    func prefillFromScan(_ result: ConsoleScanResult) {
        // Steps or Floors based on user preference
        if settingsManager.preferredWorkoutMetric == .steps {
            if let steps = result.stepsClimbed {
                metricValue = String(steps)
            }
        } else {
            if let floors = result.floorsClimbed {
                metricValue = String(Int(floors))
            }
        }

        // Duration
        if let seconds = result.elapsedTimeSeconds {
            setDuration(
                hours: seconds / 3600,
                minutes: (seconds % 3600) / 60,
                seconds: seconds % 60
            )
        }

        // Calories
        if let calories = result.calories {
            caloriesBurned = String(Int(calories))
        }

        // Heart rate (use as average)
        if let hr = result.heartRateBpm {
            avgHeartRate = String(hr)
        }
    }

    // MARK: - Prefill from Routine Completion

    /// Prefill form fields from a completed routine session
    func prefillFromRoutine(
        name: String,
        duration: TimeInterval,
        weightConfiguration: WeightConfiguration?,
        difficulty: Int?
    ) {
        // Use routine name as workout name
        workoutName = name

        // Set duration from elapsed time
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        setDuration(hours: hours, minutes: minutes, seconds: seconds)

        // Set weight configuration if available
        if let config = weightConfiguration {
            self.weightConfiguration = config
        }

        // Map routine difficulty to effort rating (1:1 with unified labels)
        if let difficulty = difficulty {
            self.effortRating = Double(difficulty)
        }
    }

    // MARK: - Computed Properties
    var isFormValid: Bool {
        // Steps/floors is optional - only validate if provided
        let metricValid = metricValue.isEmpty || Int(metricValue) != nil

        // Workout name is optional - will use default if empty
        let nameValid = workoutName.isEmpty || workoutName.count <= 50

        let basicValidation = nameValid &&
        !durationMinutes.isEmpty &&
        !durationSeconds.isEmpty &&
        metricValid &&
        Int(durationMinutes) != nil &&
        Int(durationSeconds) != nil &&
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

            // Create workout without photos - they'll be uploaded asynchronously
            let workout = try await workoutService.createWorkout(from: request)

            // Calculate and store percentile scores for heat map
            let existingWorkouts = try fetchAllWorkouts(from: modelContext)
            let percentileScores = PercentileScoreService.calculateAllPercentiles(
                for: workout,
                existingWorkouts: existingWorkouts,
                fitnessLevel: settingsManager.fitnessLevel,
                preferredMetric: settingsManager.preferredWorkoutMetric
            )
            workout.percentileScores = percentileScores

            modelContext.insert(workout)
            try modelContext.save()

            // Recalculate all PRs based on chronological workout order
            // This ensures PRs are correct even if the user logs a workout with an older date
            try PersonalRecordService.recalculateAllPersonalRecords(
                modelContext: modelContext,
                measurementSystem: settingsManager.measurementSystem,
                stepHeight: settingsManager.stepHeight
            )

            // Queue media uploads asynchronously (fire-and-forget)
            // This happens in background so form can close immediately
            if !selectedImages.isEmpty {
                let highlightedIndex = highlightedSelectedItemId.flatMap { id in
                    selectedImages.firstIndex(where: { $0.id == id })
                }
                let imagesToUpload = selectedImages
                let workoutId = workout.id
                Task {
                    try? await MediaUploadManager.shared.queueUploads(
                        for: workoutId,
                        photos: imagesToUpload,
                        highlightedIndex: highlightedIndex,
                        modelContext: modelContext
                    )
                }
            }

            // Fire-and-forget Strava auto-sync (doesn't block save)
            let stravaManager = StravaManager.shared
            if FeatureFlags.isStravaEnabled && stravaManager.isConnected && stravaManager.autoSyncEnabled {
                let primaryMetric = settingsManager.preferredWorkoutMetric
                Task {
                    do {
                        guard !workout.isSyncedToStrava else { return }
                        let activityId = try await stravaManager.syncWorkout(
                            workout,
                            primaryMetric: primaryMetric
                        )
                        workout.setStravaSyncMetadata(StravaSyncMetadata(stravaActivityId: activityId))
                        try? modelContext.save()
                    } catch {
                        print("Strava auto-sync failed: \(error)")
                    }
                }
            }

            isUploading = false

            // Don't clean up video files here - MediaUploadManager needs them
            // They'll be cleaned up after successful upload

            return workout

        } catch {
            isUploading = false
            // Clean up temp video files on failure (since we won't be uploading)
            cleanupVideoFiles()
            uploadError = error.userFriendlyMessage
            throw error
        }
    }
    
    /// Clean up temporary video files
    func cleanupVideoFiles() {
        for item in selectedImages {
            if let videoURL = item.videoURL {
                try? FileManager.default.removeItem(at: videoURL)
            }
        }
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
            durationFormatted = "\(minutes < 10 ? "0" : "")\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
        } else {
            // Show as H:MM:SS
            durationFormatted = "\(hours):\(minutes < 10 ? "0" : "")\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
        }

        // Update individual components for saving
        durationHours = hours < 10 ? "0\(hours)" : "\(hours)"
        durationMinutes = minutes < 10 ? "0\(minutes)" : "\(minutes)"
        durationSeconds = seconds < 10 ? "0\(seconds)" : "\(seconds)"
    }

    func setDuration(hours: Int, minutes: Int, seconds: Int) {
        let clampedHours = min(max(hours, 0), 999)
        let clampedMinutes = min(max(minutes, 0), 59)
        let clampedSeconds = min(max(seconds, 0), 59)

        let hasHours = clampedHours > 0
        durationHours = clampedHours < 10 ? "0\(clampedHours)" : "\(clampedHours)"
        durationMinutes = clampedMinutes < 10 ? "0\(clampedMinutes)" : "\(clampedMinutes)"
        durationSeconds = clampedSeconds < 10 ? "0\(clampedSeconds)" : "\(clampedSeconds)"

        if hasHours {
            durationFormatted = "\(clampedHours):\(clampedMinutes < 10 ? "0" : "")\(clampedMinutes):\(clampedSeconds < 10 ? "0" : "")\(clampedSeconds)"
        } else {
            durationFormatted = "\(clampedMinutes < 10 ? "0" : "")\(clampedMinutes):\(clampedSeconds < 10 ? "0" : "")\(clampedSeconds)"
        }

        let hoursDigits = hasHours ? String(clampedHours) : ""
        rawDurationDigits = hoursDigits + "\(clampedMinutes < 10 ? "0" : "")\(clampedMinutes)\(clampedSeconds < 10 ? "0" : "")\(clampedSeconds)"
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
              let seconds = Int(durationSeconds) else {
            throw WorkoutFormError.invalidInput
        }
        
        // Steps/floors is optional - default to 0 if not provided
        let value = Int(metricValue) ?? 0

        let hours = Int(durationHours) ?? 0
        let totalDuration = TimeInterval(hours * 3600 + minutes * 60 + seconds)

        let avgHR = !avgHeartRate.isEmpty ? Int(avgHeartRate) : nil
        let maxHR = !maxHeartRate.isEmpty ? Int(maxHeartRate) : nil
        let calories = !caloriesBurned.isEmpty ? Int(caloriesBurned) : nil
        
        // Snapshot the current stepsPerFloor setting
        let stepsPerFloor = settingsManager.stepsPerFloor
        
        // Calculate both steps and floors based on which metric user entered
        let steps: Int
        let floors: Int
        
        if settingsManager.preferredWorkoutMetric == .steps {
            steps = value
            floors = Workout.stepsToFloors(value, stepsPerFloor: stepsPerFloor)
        } else {
            floors = value
            steps = Workout.floorsToSteps(value, stepsPerFloor: stepsPerFloor)
        }

        // Only include weight configuration if it has enabled entries
        let weights = weightConfiguration.isEmpty ? nil : weightConfiguration

        return CreateWorkoutRequest(
            name: workoutName.isEmpty ? Workout.generateDefaultName(for: workoutDate) : workoutName,
            date: workoutDate,
            duration: totalDuration,
            steps: steps,
            floors: floors,
            stepsPerFloor: stepsPerFloor,
            notes: notes,
            avgHeartRate: avgHR,
            maxHeartRate: maxHR,
            caloriesBurned: calories,
            effortRating: effortRating,
            weightConfiguration: weights
        )
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

    /// Fetch all workouts from the model context for percentile calculation
    private func fetchAllWorkouts(from modelContext: ModelContext) throws -> [Workout] {
        let descriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
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
