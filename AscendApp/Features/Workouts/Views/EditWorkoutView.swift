//
//  EditWorkoutView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/28/25.
//

import PhotosUI
import SwiftUI
import SwiftData

struct EditWorkoutView: View {
    let workout: Workout
    @Binding var showingEditWorkout: Bool
    let title: String
    let primaryActionTitle: String
    let cancelActionTitle: String?
    let destructiveActionTitle: String?
    let onSave: (() -> Void)?
    let onCancel: (() -> Void)?
    let onDestructiveAction: (() -> Void)?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var settingsManager = SettingsManager.shared
    @State private var themeManager = ThemeManager.shared
    
    @State private var workoutName: String = ""
    @State private var workoutDate = Date()
    @State private var durationHours: String = ""
    @State private var durationMinutes: String = ""
    @State private var durationSeconds: String = ""
    @State private var metricValue: String = ""
    @State private var notes: String = ""
    @State private var showingMetricTooltip = false
    @State private var selectedImages: [SelectedPhotoItem] = []
    @State private var existingPhotos: [Photo] = []
    @State private var photosMarkedForDeletion: [Photo] = []
    @State private var photoPendingDeletion: Photo?
    @State private var photoForAction: Photo?
    @State private var highlightSelection: HighlightSelection?
    @State private var updateErrorMessage: String?
    @State private var isSaving = false
    @State private var showMediaLimitAlert = false
    @State private var mediaLimitMessage = ""
    
    // Health Metrics
    @State private var avgHeartRate: String = ""
    @State private var maxHeartRate: String = ""
    @State private var caloriesBurned: String = ""
    @State private var durationFormatted: String = ""

    // Weight Equipment
    @State private var weightConfiguration: WeightConfiguration = .empty
    @State private var showingDatePicker = false
    @State private var effortRating: Double? = nil
    @State private var showingEffortRating = false
    @State private var showingDurationPicker = false
    @State private var durationPickerHours = 0
    @State private var durationPickerMinutes = 0
    @State private var durationPickerSeconds = 0
    
    @FocusState private var focusedField: WorkoutFormField?
    
    private let photoService = PhotoService()

    init(
        workout: Workout,
        showingEditWorkout: Binding<Bool>,
        title: String = "Edit Workout",
        primaryActionTitle: String = "Update",
        cancelActionTitle: String? = "Cancel",
        destructiveActionTitle: String? = nil,
        onSave: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onDestructiveAction: (() -> Void)? = nil
    ) {
        self.workout = workout
        self._showingEditWorkout = showingEditWorkout
        self.title = title
        self.primaryActionTitle = primaryActionTitle
        self.cancelActionTitle = cancelActionTitle
        self.destructiveActionTitle = destructiveActionTitle
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDestructiveAction = onDestructiveAction
    }
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    private var highlightedSelectedItemBinding: Binding<UUID?> {
        Binding(
            get: {
                if case .selectedItem(let id) = highlightSelection {
                    return id
                }
                return nil
            },
            set: { newValue in
                if let id = newValue {
                    highlightSelection = .selectedItem(id)
                } else if case .selectedItem = highlightSelection {
                    highlightSelection = fallbackHighlightSelection()
                }
            }
        )
    }
    
    private var isFormValid: Bool {
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
        
        return basicValidation && durationValid && avgHRValid && maxHRValid && caloriesValid && !isSaving
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Always visible header
                permanentHeader
                
                // Scrollable content
                scrollContent
            }
            .themedBackground()
            .navigationBarHidden(true)
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    KeyboardDismissButton()
                }
            }
        }
        .sheet(isPresented: $showingMetricTooltip) {
            MetricTooltipView()
                .appSheetStyle(.fitted())
        }
        .sheet(isPresented: $showingDatePicker) {
            DateTimePickerView(selectedDate: $workoutDate)
                .appSheetStyle(.dateTimePicker)
        }
        .sheet(isPresented: $showingEffortRating) {
            EffortRatingView(effortRating: $effortRating)
                .appSheetStyle(.effortRating)
        }
        .sheet(isPresented: $showingDurationPicker) {
            DurationPickerSheet(
                hours: $durationPickerHours,
                minutes: $durationPickerMinutes,
                seconds: $durationPickerSeconds
            ) {
                setDuration(hours: durationPickerHours, minutes: durationPickerMinutes, seconds: durationPickerSeconds)
                showingDurationPicker = false
            }
            .appSheetStyle(.durationPicker, isInteractiveDismissDisabled: true)
        }
        .sheet(item: $photoPendingDeletion) { photo in
            DeletePhotoConfirmationView(
                onDelete: {
                    removeExistingPhoto(photo)
                },
                onCancel: {
                    photoPendingDeletion = nil
                }
            )
        }
        .sheet(item: $photoForAction) { photo in
            PhotoActionSheet(
                photo: photo,
                isHighlighted: isPhotoHighlighted(photo),
                onMakeHighlighted: {
                    makePhotoHighlighted(photo)
                    photoForAction = nil
                },
                onDelete: {
                    removeExistingPhoto(photo)
                    photoForAction = nil
                },
                onCancel: {
                    photoForAction = nil
                }
            )
        }
        .alert("Unable to Update", isPresented: Binding(
            get: { updateErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    updateErrorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                updateErrorMessage = nil
            }
        } message: {
            Text(updateErrorMessage ?? "")
        }
        .onAppear {
            populateFields()
        }
        .onChange(of: selectedImages.map(\.id)) {
            ensureHighlightSelectionIsValid()
        }
        .onChange(of: existingPhotos.map(\.id)) {
            ensureHighlightSelectionIsValid()
        }
    }
    
    private var permanentHeader: some View {
        VStack(spacing: 0) {
            HStack {
                if let cancelActionTitle {
                    Button(cancelActionTitle) {
                        cleanupVideoFiles()
                        onCancel?()
                        showingEditWorkout = false
                    }
                    .font(.montserratRegular)
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    .frame(minWidth: 80, alignment: .leading)
                } else {
                    Color.clear
                        .frame(width: 80, height: 1)
                }

                Spacer()

                Text(title)
                    .font(.montserratSemiBold(size: 18))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Spacer()

                Button(action: {
                    Task {
                        await updateWorkout()
                    }
                }) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .accent))
                    } else {
                        Text(primaryActionTitle)
                    }
                }
                .font(.montserratSemiBold)
                .foregroundStyle(isFormValid ? .accent : .gray)
                .disabled(!isFormValid)
                .frame(minWidth: 80)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .background(effectiveColorScheme == .dark ? .black : .white)

            Divider()
                .background(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))
        }
        .background(effectiveColorScheme == .dark ? .black : .white)
    }
    
    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 20) {
                    workoutInfoCard
                        
                        FormSection(title: "Health Metrics") {
                            VStack(spacing: 12) {
                                // Average Heart Rate
                                FormTextField(
                                    label: "Average heart rate (BPM)",
                                    isRequired: false,
                                    keyboardType: .numberPad,
                                    text: $avgHeartRate,
                                    focusedField: $focusedField,
                                    fieldIdentifier: WorkoutFormField.avgHeartRate
                                )
                                .onChange(of: avgHeartRate) { _, newValue in
                                    avgHeartRate = filterNumericInput(newValue)
                                }

                                // Maximum Heart Rate
                                FormTextField(
                                    label: "Maximum heart rate (BPM)",
                                    isRequired: false,
                                    keyboardType: .numberPad,
                                    text: $maxHeartRate,
                                    focusedField: $focusedField,
                                    fieldIdentifier: WorkoutFormField.maxHeartRate
                                )
                                .onChange(of: maxHeartRate) { _, newValue in
                                    maxHeartRate = filterNumericInput(newValue)
                                }

                                // Calories Burned
                                FormTextField(
                                    label: "Calories burned",
                                    isRequired: false,
                                    keyboardType: .numberPad,
                                    text: $caloriesBurned,
                                    focusedField: $focusedField,
                                    fieldIdentifier: WorkoutFormField.caloriesBurned
                                )
                                .onChange(of: caloriesBurned) { _, newValue in
                                    caloriesBurned = filterNumericInput(newValue)
                                }
                            }
                        }

                        FormSection(title: "Weights Used") {
                            WeightEntryView(
                                configuration: $weightConfiguration,
                                measurementSystem: settingsManager.measurementSystem
                            )
                        }

                        if let destructiveActionTitle {
                            Button(role: .destructive) {
                                onDestructiveAction?()
                            } label: {
                                Text(destructiveActionTitle)
                            }
                            .appSheetButtonStyle(tone: .destructive)
                            .disabled(isSaving)
                        }
                    }

                    Spacer(minLength: 40)
                }
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .onChange(of: focusedField) { oldFocus, newFocus in
                // Validate fields when focus changes
                if oldFocus == .avgHeartRate {
                    validateHeartRateOnSubmit($avgHeartRate)
                } else if oldFocus == .maxHeartRate {
                    validateHeartRateOnSubmit($maxHeartRate)
                } else if oldFocus == .caloriesBurned {
                    validateCaloriesOnSubmit()
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }

    private var workoutInfoCard: some View {
        VStack(spacing: 16) {
            // Workout Name (optional - uses default if empty)
            FormTextField(
                label: "Workout Name",
                isRequired: false,
                text: $workoutName,
                focusedField: $focusedField,
                fieldIdentifier: WorkoutFormField.workoutName,
                maxLength: 50
            )

            // Description
            FormTextEditor(
                label: "Description",
                isRequired: false,
                placeholder: "Add a description for your workout",
                text: $notes,
                focusedField: $focusedField,
                fieldIdentifier: WorkoutFormField.notes
            )
            
            if existingPhotos.isEmpty {
                PhotoGalleryView(
                    selectedImages: $selectedImages,
                    highlightedSelectedItemId: highlightedSelectedItemBinding,
                    existingMediaCount: existingPhotos.count,
                    existingVideoCount: existingPhotos.filter { $0.isVideo }.count
                )
            } else {
                existingPhotosSection
            }
            
            FormSection(title: "Workout Details") {
                VStack(spacing: 12) {
                    // Date *
                    FormButton(
                        label: "Date",
                        isRequired: true,
                        icon: "calendar",
                        value: formatWorkoutDateTime(),
                        action: { showingDatePicker = true }
                    )

                    // Duration *
                    FormButton(
                        label: "Duration",
                        isRequired: true,
                        icon: "clock",
                        value: durationFormatted.isEmpty ? nil : durationFormatted,
                        action: {
                            syncDurationPicker()
                            showingDurationPicker = true
                        }
                    )

                    // Steps/Floors
                    FormTextField(
                        label: settingsManager.preferredWorkoutMetric.unit.capitalized,
                        isRequired: false,
                        icon: settingsManager.preferredWorkoutMetric == .steps ? "figure.stairs" : "building.2",
                        keyboardType: .numberPad,
                        text: $metricValue,
                        focusedField: $focusedField,
                        fieldIdentifier: WorkoutFormField.metricValue
                    )
                    .onChange(of: metricValue) { _, newValue in
                        metricValue = filterNumericInput(newValue)
                    }

                    // Effort Rating
                    FormButton(
                        label: "Effort rating",
                        isRequired: false,
                        value: effortRating != nil ? effortRatingDisplayText() : nil,
                        action: { showingEffortRating = true }
                    )
                }
            }
            
        }
    }
    
    @ViewBuilder
    private var existingPhotosSection: some View {
        if !existingPhotos.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Current Media")
                        .font(.montserratSemiBold(size: 18))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    
                    Spacer()
                }
                
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(existingPhotos) { photo in
                            ZStack(alignment: .topLeading) {
                                LoadablePhotoView(
                                    photo: photo,
                                    size: CGSize(width: 120, height: 120),
                                    cornerRadius: 12
                                ) {
                                    photoForAction = photo
                                }
                                .overlay(alignment: .topTrailing) {
                                    MediaTileDeleteButton {
                                        photoPendingDeletion = photo
                                    }
                                    .padding(6)
                                }
                                
                                // Highlighted indicator
                                if isPhotoHighlighted(photo) {
                                    MediaTileHighlightBadge()
                                        .padding(6)
                                }
                            }
                            .contextMenu {
                                if !isPhotoHighlighted(photo) {
                                    Button {
                                        makePhotoHighlighted(photo)
                                    } label: {
                                        Label(photo.isVideo ? "Make Highlighted Video" : "Make Highlighted Photo", systemImage: "star.fill")
                                    }
                                }
                                
                                Button(role: .destructive) {
                                    photoPendingDeletion = photo
                                } label: {
                                    Label(photo.isVideo ? "Delete Video" : "Delete Photo", systemImage: "trash")
                                }
                            }
                        }

                        PhotoGalleryView(
                            selectedImages: $selectedImages,
                            highlightedSelectedItemId: highlightedSelectedItemBinding,
                            existingMediaCount: existingPhotos.count,
                            existingVideoCount: existingPhotos.filter { $0.isVideo }.count,
                            embeddedInScrollRow: true
                        )
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func isPhotoHighlighted(_ photo: Photo) -> Bool {
        switch highlightSelection {
        case .existingPhoto(let id):
            return id == photo.id
        case .selectedItem:
            return false
        case .none:
            return existingPhotos.first?.id == photo.id
        }
    }
    
    private func makePhotoHighlighted(_ photo: Photo) {
        highlightSelection = .existingPhoto(photo.id)
        workout.setHighlightedPhoto(photo.id)
        try? modelContext.save()
    }
    
    // MARK: - Helper Functions (Same as WorkoutFormView)
    private func populateFields() {
        workoutName = workout.name
        workoutDate = workout.date
        notes = workout.notes
        
        // Duration
        let hours = Int(workout.duration) / 3600
        let minutes = (Int(workout.duration) % 3600) / 60
        let seconds = Int(workout.duration) % 60
        
        durationHours = hours < 10 ? "0\(hours)" : "\(hours)"
        durationMinutes = minutes < 10 ? "0\(minutes)" : "\(minutes)"
        durationSeconds = seconds < 10 ? "0\(seconds)" : "\(seconds)"

        if hours == 0 {
            durationFormatted = "\(minutes < 10 ? "0" : "")\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
        } else {
            durationFormatted = "\(hours):\(minutes < 10 ? "0" : "")\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
        }
        
        // Primary metric value based on user preference
        metricValue = String(workout.metricValue(for: settingsManager.preferredWorkoutMetric))
        
        // Health metrics
        avgHeartRate = workout.avgHeartRate != nil ? String(workout.avgHeartRate!) : ""
        maxHeartRate = workout.maxHeartRate != nil ? String(workout.maxHeartRate!) : ""
        caloriesBurned = workout.caloriesBurned != nil ? String(workout.caloriesBurned!) : ""
        effortRating = workout.effortRating

        // Weight configuration
        weightConfiguration = workout.weightConfiguration ?? .empty

        existingPhotos = workout.photos
        if let highlightedId = workout.highlightedPhotoId {
            highlightSelection = .existingPhoto(highlightedId)
        } else if let firstPhoto = workout.photos.first {
            highlightSelection = .existingPhoto(firstPhoto.id)
        } else {
            highlightSelection = nil
        }
        photosMarkedForDeletion = []
        selectedImages = []
    }
    
    private func syncDurationPicker() {
        durationPickerHours = Int(durationHours) ?? 0
        durationPickerMinutes = Int(durationMinutes) ?? 0
        durationPickerSeconds = Int(durationSeconds) ?? 0
    }

    private func formatDurationInput(_ input: String) {
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

    private func setDuration(hours: Int, minutes: Int, seconds: Int) {
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
    }
    
    private func validateHeartRateOnSubmit(_ field: Binding<String>) {
        let digits = field.wrappedValue.filter { $0.isNumber }
        if digits.isEmpty { 
            field.wrappedValue = ""
            return 
        }
        
        guard let value = Int(digits) else { return }
        
        if value < 25 { 
            field.wrappedValue = "25" 
        } else if value > 230 { 
            field.wrappedValue = "230" 
        } else {
            field.wrappedValue = String(value)
        }
    }
    
    private func validateCaloriesOnSubmit() {
        let digits = caloriesBurned.filter { $0.isNumber }
        if digits.isEmpty { 
            caloriesBurned = ""
            return 
        }
        
        guard let value = Int(digits) else { return }
        caloriesBurned = value < 0 ? "0" : String(value)
    }
    
    private func filterNumericInput(_ input: String) -> String {
        return input.filter { $0.isNumber }
    }
    
    private func effortRatingDisplayText() -> String {
        guard let rating = effortRating else {
            return "Add effort rating (optional)"
        }
        
        let ratingInt = Int(rating)
        let description = effortDescription(for: rating)
        return "Effort: \(ratingInt)/5 - \(description)"
    }
    
    private func effortDescription(for rating: Double) -> String {
        switch Int(rating) {
        case 1:
            return "Minimal"
        case 2:
            return "Light"
        case 3:
            return "Moderate"
        case 4:
            return "High"
        case 5:
            return "Maximum"
        default:
            return "Moderate"
        }
    }
    
    private func formatWorkoutDateTime() -> String {
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
    
    @MainActor
    private func updateWorkout() async {
        print("🔍 Update workout called")
        print("🔍 Form valid: \(isFormValid)")
        
        guard !isSaving else { return }
        guard let minutes = Int(durationMinutes),
              let seconds = Int(durationSeconds) else {
            print("❌ Guard failed - invalid number conversion")
            return
        }
        
        // Steps/floors is optional - default to 0 if not provided
        let value = Int(metricValue) ?? 0

        // Calculate both metric values from the user's primary metric
        let steps: Int
        let floors: Int
        if settingsManager.preferredWorkoutMetric == .steps {
            steps = value
            floors = Workout.stepsToFloors(value, stepsPerFloor: workout.stepsPerFloor)
        } else {
            floors = value
            steps = Workout.floorsToSteps(value, stepsPerFloor: workout.stepsPerFloor)
        }
        
        ensureHighlightSelectionIsValid()
        isSaving = true
        updateErrorMessage = nil
        
        let hours = Int(durationHours) ?? 0
        let totalDuration = TimeInterval(hours * 3600 + minutes * 60 + seconds)
        
        // Convert health metrics, only include if values entered
        let avgHR = !avgHeartRate.isEmpty ? Int(avgHeartRate) : nil
        let maxHR = !maxHeartRate.isEmpty ? Int(maxHeartRate) : nil
        let calories = !caloriesBurned.isEmpty ? Int(caloriesBurned) : nil
        
        let selectedImagesSnapshot = selectedImages
        var newlyUploadedPhotos: [Photo] = []
        let leaderboardSnapshotBeforeEdit = LeaderboardWorkoutSnapshot(workout: workout)
        
        do {
            if !selectedImagesSnapshot.isEmpty {
                newlyUploadedPhotos = try await photoService.uploadSelectedPhotos(selectedImagesSnapshot)
            }
            
            // Update the workout properties
            workout.name = workoutName.isEmpty ? Workout.generateDefaultName(for: workoutDate) : workoutName
            workout.date = workoutDate
            workout.duration = totalDuration
            workout.notes = notes
            workout.avgHeartRate = avgHR
            workout.maxHeartRate = maxHR
            workout.caloriesBurned = calories
            workout.effortRating = effortRating

            // Update weight configuration
            workout.weightConfiguration = weightConfiguration.isEmpty ? nil : weightConfiguration

            // Update both metric values
            workout.steps = steps
            workout.floors = floors
            
            // Persist new/existing photos
            let combinedPhotos = existingPhotos + newlyUploadedPhotos
            workout.photos = combinedPhotos
            
            if let resolvedHighlight = resolvedHighlightId(
                combinedPhotos: combinedPhotos,
                newlyUploadedPhotos: newlyUploadedPhotos,
                selectedSnapshot: selectedImagesSnapshot
            ) {
                workout.highlightedPhotoId = resolvedHighlight
            } else if workout.highlightedPhotoId == nil {
                workout.highlightedPhotoId = combinedPhotos.first?.id
            }
            
            try modelContext.save()
            print("✅ Successfully updated workout with \(workout.photos.count) photos")

            // Recalculate PRs and leaderboard stats after edit
            try WorkoutMutationHandler.shared.workoutsDidChange(
                modelContext: modelContext,
                mutation: .updated(
                    before: leaderboardSnapshotBeforeEdit,
                    after: LeaderboardWorkoutSnapshot(workout: workout)
                )
            )
            
            let photosToDelete = photosMarkedForDeletion
            if !photosToDelete.isEmpty {
                Task {
                    try? await photoService.deletePhotos(photosToDelete)
                }
            }

            // Clean up video files
            cleanupVideoFiles()

            showingEditWorkout = false
            onSave?()
        } catch {
            if !newlyUploadedPhotos.isEmpty {
                Task {
                    try? await photoService.deletePhotos(newlyUploadedPhotos)
                }
            }
            // Clean up temp video files on failure
            cleanupVideoFiles()
            print("❌ Error updating workout: \(error)")
            updateErrorMessage = error.userFriendlyMessage
        }

        isSaving = false
    }
    
    private func removeExistingPhoto(_ photo: Photo) {
        if !photosMarkedForDeletion.contains(where: { $0.id == photo.id }) {
            photosMarkedForDeletion.append(photo)
        }
        existingPhotos.removeAll { $0.id == photo.id }
        
        if case .existingPhoto(let id) = highlightSelection, id == photo.id {
            highlightSelection = fallbackHighlightSelection()
        }
        
        photoPendingDeletion = nil
    }
    
    private func cleanupVideoFiles() {
        for item in selectedImages {
            if let videoURL = item.videoURL {
                try? FileManager.default.removeItem(at: videoURL)
            }
        }
    }
    
    private func ensureHighlightSelectionIsValid() {
        switch highlightSelection {
        case .existingPhoto(let id):
            if !existingPhotos.contains(where: { $0.id == id }) {
                highlightSelection = fallbackHighlightSelection()
            }
        case .selectedItem(let id):
            if !selectedImages.contains(where: { $0.id == id }) {
                highlightSelection = fallbackHighlightSelection()
            }
        case .none:
            highlightSelection = fallbackHighlightSelection()
        }
    }
    
    private func fallbackHighlightSelection() -> HighlightSelection? {
        if let firstExisting = existingPhotos.first {
            workout.highlightedPhotoId = firstExisting.id
            return .existingPhoto(firstExisting.id)
        } else if let firstSelected = selectedImages.first {
            return .selectedItem(firstSelected.id)
        } else {
            workout.highlightedPhotoId = nil
            return nil
        }
    }
    
    private func resolvedHighlightId(
        combinedPhotos: [Photo],
        newlyUploadedPhotos: [Photo],
        selectedSnapshot: [SelectedPhotoItem]
    ) -> UUID? {
        switch highlightSelection {
        case .existingPhoto(let id):
            return combinedPhotos.first(where: { $0.id == id })?.id
        case .selectedItem(let selectedId):
            if let index = selectedSnapshot.firstIndex(where: { $0.id == selectedId }),
               index < newlyUploadedPhotos.count {
                return newlyUploadedPhotos[index].id
            }
            return nil
        case .none:
            return nil
        }
    }
    
    private enum HighlightSelection: Equatable {
        case existingPhoto(UUID)
        case selectedItem(UUID)
    }
}

#Preview {
    @Previewable @State var showEdit = true

    let sampleWorkout = Workout(
        name: "Morning Stair Climb",
        date: Date(),
        duration: 1800, // 30 minutes
        steps: 2500,
        floors: 156,
        stepsPerFloor: 16,
        notes: "Great morning workout!",
        avgHeartRate: 145,
        maxHeartRate: 165,
        caloriesBurned: 320,
        effortRating: 4.0
    )
    
    EditWorkoutView(workout: sampleWorkout, showingEditWorkout: $showEdit)
        .modelContainer(for: [Workout.self, WorkoutSourceLink.self], inMemory: true)
}
