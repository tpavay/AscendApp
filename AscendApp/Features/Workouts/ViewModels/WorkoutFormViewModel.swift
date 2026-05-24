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
    var stepsValue: String = ""
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
    private var routineAttribution: RoutineWorkoutAttribution?

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

    // MARK: - Prefill from Routine Completion

    /// Prefill form fields from a completed routine session
    func prefillFromRoutine(
        name: String,
        duration: TimeInterval,
        weightConfiguration: WeightConfiguration?,
        difficulty: Int?,
        attribution: RoutineWorkoutAttribution? = nil
    ) {
        // Use routine name as workout name
        workoutName = name
        routineAttribution = attribution

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
        let stepsValid = WorkoutInputValidation.isValidOptionalSteps(stepsValue)

        // Workout name is optional - will use default if empty
        let nameValid = WorkoutInputValidation.isValidWorkoutName(workoutName)
        let notesValid = WorkoutInputValidation.isValidNotes(notes)

        let basicValidation = nameValid &&
        notesValid &&
        !durationMinutes.isEmpty &&
        !durationSeconds.isEmpty &&
        stepsValid &&
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
        let workoutTotalsValid = WorkoutInputValidation.isValidWorkoutTotals(
            stepsValue: stepsValue,
            durationHours: hours,
            durationMinutes: minutes,
            durationSeconds: seconds
        )

        // Validate health metrics if provided
        let avgHRValid = WorkoutInputValidation.isValidOptionalHeartRate(avgHeartRate)
        let maxHRValid = WorkoutInputValidation.isValidOptionalHeartRate(maxHeartRate)
        let caloriesValid = WorkoutInputValidation.isValidOptionalCalories(caloriesBurned)

        return basicValidation && durationValid && workoutTotalsValid && avgHRValid && maxHRValid && caloriesValid && !isUploading
    }

    // MARK: - Actions
    func saveWorkout(to modelContext: ModelContext) async throws -> Workout {
        guard isFormValid else {
            throw WorkoutFormError.invalidForm
        }

        isUploading = true
        uploadError = nil
        defer { isUploading = false }

        do {
            let request = try createWorkoutRequest()

            // Create workout without photos - they'll be uploaded asynchronously
            let workout = try await workoutService.createWorkout(from: request)

            modelContext.insert(workout)
            try WorkoutParticipationService.addRoutineParticipationIfNeeded(
                for: workout,
                attribution: routineAttribution,
                userId: nil,
                modelContext: modelContext
            )
            try modelContext.save()

            // Refresh derived workout data and leaderboard stats.
            try WorkoutMutationHandler.shared.workoutsDidChange(
                modelContext: modelContext,
                mutation: .created([LeaderboardWorkoutSnapshot(workout: workout)]),
                newWorkouts: [workout],
                changedWorkouts: [workout]
            )

            // Queue media uploads asynchronously (fire-and-forget)
            // This happens in background so form can close immediately
            if !selectedImages.isEmpty {
                let highlightedIndex = highlightedSelectedItemId.flatMap { id in
                    selectedImages.firstIndex(where: { $0.id == id })
                }
                queueMediaUploadsInBackground(
                    for: workout.id,
                    highlightedIndex: highlightedIndex,
                    modelContext: modelContext
                )
            }

            // Don't clean up video files here - MediaUploadManager needs them
            // They'll be cleaned up after successful upload

            return workout

        } catch {
            // Clean up temp video files on failure (since we won't be uploading)
            cleanupVideoFiles()
            uploadError = error.userFriendlyMessage
            throw error
        }
    }
    
    /// Clean up temporary video files
    func cleanupVideoFiles() {
        SelectedMediaPreparationService.cleanupTemporaryVideoFiles(in: selectedImages)
    }

    private func queueMediaUploadsInBackground(
        for workoutId: UUID,
        highlightedIndex: Int?,
        modelContext: ModelContext
    ) {
        let imagesToUpload = selectedImages

        Task { @MainActor in
            do {
                try await MediaUploadManager.shared.queueUploads(
                    for: workoutId,
                    photos: imagesToUpload,
                    highlightedIndex: highlightedIndex,
                    modelContext: modelContext
                )
            } catch {
                TelemetryManager.shared.recordError(
                    error,
                    context: .storage,
                    code: "media_upload_queue_failed"
                )
                print("Media upload queue failed: \(error)")
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

        // Parse and format using the new utility
        let (h, m, s) = DurationFormatter.parse(rawDigits: rawDurationDigits)
        durationFormatted = DurationFormatter.format(hours: h, minutes: m, seconds: s)

        // Update individual components for saving
        durationHours = h < 10 ? "0\(h)" : "\(h)"
        durationMinutes = m < 10 ? "0\(m)" : "\(m)"
        durationSeconds = s < 10 ? "0\(s)" : "\(s)"
    }

    func setDuration(hours: Int, minutes: Int, seconds: Int) {
        let clampedHours = min(max(hours, 0), 999)
        let clampedMinutes = min(max(minutes, 0), 59)
        let clampedSeconds = min(max(seconds, 0), 59)

        durationFormatted = DurationFormatter.format(hours: clampedHours, minutes: clampedMinutes, seconds: clampedSeconds)
        
        durationHours = clampedHours < 10 ? "0\(clampedHours)" : "\(clampedHours)"
        durationMinutes = clampedMinutes < 10 ? "0\(clampedMinutes)" : "\(clampedMinutes)"
        durationSeconds = clampedSeconds < 10 ? "0\(clampedSeconds)" : "\(clampedSeconds)"

        let hoursDigits = clampedHours > 0 ? String(clampedHours) : ""
        rawDurationDigits = hoursDigits + "\(clampedMinutes < 10 ? "0" : "")\(clampedMinutes)\(clampedSeconds < 10 ? "0" : "")\(clampedSeconds)"
    }

    func validateHeartRateOnSubmit(_ value: String) -> String {
        WorkoutInputValidation.normalizeHeartRateOnSubmit(value)
    }

    func validateCaloriesOnSubmit(_ value: String) -> String {
        WorkoutInputValidation.normalizeCaloriesOnSubmit(value)
    }

    func filterNumericInput(_ input: String) -> String {
        WorkoutInputValidation.filterNumericInput(input)
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
        
        let steps = Int(stepsValue) ?? 0
        let floors = Workout.stepsToFloors(steps)

        let hours = Int(durationHours) ?? 0
        let totalDuration = TimeInterval(hours * 3600 + minutes * 60 + seconds)

        let avgHR = !avgHeartRate.isEmpty ? Int(avgHeartRate) : nil
        let maxHR = !maxHeartRate.isEmpty ? Int(maxHeartRate) : nil
        let calories = !caloriesBurned.isEmpty ? Int(caloriesBurned) : nil
        
        // Only include weight configuration if it has enabled entries
        let weights = weightConfiguration.isEmpty ? nil : weightConfiguration

        return CreateWorkoutRequest(
            name: workoutName.isEmpty ? Workout.generateDefaultName(for: workoutDate) : workoutName,
            date: workoutDate,
            duration: totalDuration,
            steps: steps,
            floors: floors,
            stepsPerFloor: Workout.defaultStepsPerFloor,
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
