//
//  WorkoutFormView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import PhotosUI
import SwiftUI
import SwiftData

/// Data to prefill the workout form from a completed routine
struct RoutinePrefillData {
    let name: String
    let startedAt: Date
    let duration: TimeInterval
    let weightConfiguration: WeightConfiguration?
    let difficulty: Int?
    let attribution: RoutineWorkoutAttribution?

    init(
        name: String,
        startedAt: Date,
        duration: TimeInterval,
        weightConfiguration: WeightConfiguration?,
        difficulty: Int?,
        attribution: RoutineWorkoutAttribution? = nil
    ) {
        self.name = name
        self.startedAt = startedAt
        self.duration = duration
        self.weightConfiguration = weightConfiguration
        self.difficulty = difficulty
        self.attribution = attribution
    }
}

struct WorkoutFormView: View {
    @Binding var showingWorkoutForm: Bool
    let onWorkoutCompleted: (Workout) -> Void
    var routinePrefill: RoutinePrefillData? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared

    // ViewModel handles all form logic and state
    @State private var viewModel = WorkoutFormViewModel()

    // UI-only state
    @State private var showingDatePicker = false
    @State private var showingEffortRating = false
    @State private var showingDurationPicker = false
    @State private var durationPickerHours = 0
    @State private var durationPickerMinutes = 0
    @State private var durationPickerSeconds = 0
    @State private var didApplyRoutinePrefill = false

    @FocusState private var focusedField: WorkoutFormField?

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
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
            .keyboardDoneToolbar()
        }
        .sheet(isPresented: $showingDatePicker) {
            DateTimePickerView(selectedDate: $viewModel.workoutDate)
                .appSheetStyle(.dateTimePicker)
        }
        .sheet(isPresented: $showingEffortRating) {
            EffortRatingView(effortRating: $viewModel.effortRating)
                .appSheetStyle(.effortRating)
        }
        .sheet(isPresented: $showingDurationPicker) {
            DurationPickerSheet(
                hours: $durationPickerHours,
                minutes: $durationPickerMinutes,
                seconds: $durationPickerSeconds
            ) {
                viewModel.setDuration(
                    hours: durationPickerHours,
                    minutes: durationPickerMinutes,
                    seconds: durationPickerSeconds
                )
                showingDurationPicker = false
            }
            .appSheetStyle(.durationPicker, isInteractiveDismissDisabled: true)
        }
        .alert("Upload Error", isPresented: .constant(viewModel.uploadError != nil)) {
            Button("OK") {
                viewModel.uploadError = nil
            }
        } message: {
            if let error = viewModel.uploadError {
                Text(error)
            }
        }
        .onAppear {
            if viewModel.workoutName.isEmpty {
                viewModel.workoutName = Workout.generateDefaultName(for: viewModel.workoutDate)
            }
            // Apply prefill from routine completion if provided
            if let routine = routinePrefill, !didApplyRoutinePrefill {
                viewModel.prefillFromRoutine(
                    name: routine.name,
                    startedAt: routine.startedAt,
                    duration: routine.duration,
                    weightConfiguration: routine.weightConfiguration,
                    difficulty: routine.difficulty,
                    attribution: routine.attribution
                )
                didApplyRoutinePrefill = true
            }
        }
    }

    private var workoutInfoCard: some View {
        VStack(spacing: 16) {
            // Workout Name (optional - uses default if empty)
            FormTextField(
                label: "Workout Name",
                isRequired: false,
                placeholder: Workout.generateDefaultName(for: viewModel.workoutDate),
                text: $viewModel.workoutName,
                focusedField: $focusedField,
                fieldIdentifier: WorkoutFormField.workoutName,
                maxLength: WorkoutInputValidation.nameMaxLength
            )

            // Description
            FormTextEditor(
                label: "Description",
                isRequired: false,
                placeholder: "Add a description for your workout",
                text: $viewModel.notes,
                focusedField: $focusedField,
                fieldIdentifier: WorkoutFormField.notes,
                maxLength: WorkoutInputValidation.notesMaxLength
            )

            PhotoGalleryView(
                selectedImages: $viewModel.selectedImages,
                highlightedSelectedItemId: Binding(
                    get: { viewModel.highlightedSelectedItemId },
                    set: { viewModel.highlightedSelectedItemId = $0 }
                )
            )

            FormSection(title: "Workout Details") {
                VStack(spacing: 12) {
                    // Date *
                    FormButton(
                        label: "Date",
                        isRequired: true,
                        icon: "calendar",
                        value: viewModel.formatWorkoutDateTime(),
                        action: { showingDatePicker = true }
                    )

                    // Duration *
                    FormButton(
                        label: "Duration",
                        isRequired: true,
                        icon: "clock",
                        value: viewModel.durationFormatted.isEmpty ? nil : viewModel.durationFormatted,
                        action: {
                            syncDurationPickerWithViewModel()
                            showingDurationPicker = true
                        }
                    )

                    FormTextField(
                        label: "Steps",
                        isRequired: false,
                        icon: "figure.stairs",
                        keyboardType: .numberPad,
                        text: $viewModel.stepsValue,
                        focusedField: $focusedField,
                        fieldIdentifier: WorkoutFormField.stepsValue
                    )

                    // Effort Rating
                    FormButton(
                        label: "Effort rating",
                        isRequired: false,
                        value: viewModel.effortRating != nil ? viewModel.effortRatingDisplayText() : nil,
                        action: { showingEffortRating = true }
                    )
                }
            }
        }
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
                                    text: $viewModel.avgHeartRate,
                                    focusedField: $focusedField,
                                    fieldIdentifier: WorkoutFormField.avgHeartRate
                                )
                                .onChange(of: viewModel.avgHeartRate) { _, newValue in
                                    viewModel.avgHeartRate = viewModel.filterNumericInput(newValue)
                                }

                                // Maximum Heart Rate
                                FormTextField(
                                    label: "Maximum heart rate (BPM)",
                                    isRequired: false,
                                    keyboardType: .numberPad,
                                    text: $viewModel.maxHeartRate,
                                    focusedField: $focusedField,
                                    fieldIdentifier: WorkoutFormField.maxHeartRate
                                )
                                .onChange(of: viewModel.maxHeartRate) { _, newValue in
                                    viewModel.maxHeartRate = viewModel.filterNumericInput(newValue)
                                }

                                // Calories Burned
                                FormTextField(
                                    label: "Calories burned",
                                    isRequired: false,
                                    keyboardType: .numberPad,
                                    text: $viewModel.caloriesBurned,
                                    focusedField: $focusedField,
                                    fieldIdentifier: WorkoutFormField.caloriesBurned
                                )
                                .onChange(of: viewModel.caloriesBurned) { _, newValue in
                                    viewModel.caloriesBurned = viewModel.filterNumericInput(newValue)
                                }
                            }
                        }

                        FormSection(title: "Weights Used") {
                            WeightEntryView(
                                configuration: $viewModel.weightConfiguration,
                                measurementSystem: settingsManager.measurementSystem
                            )
                        }
                    }

                    Spacer(minLength: 40)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .onChange(of: focusedField) { oldFocus, newFocus in
                // Validate fields when focus changes
                if oldFocus == .avgHeartRate {
                    viewModel.avgHeartRate = viewModel.validateHeartRateOnSubmit(viewModel.avgHeartRate)
                } else if oldFocus == .maxHeartRate {
                    viewModel.maxHeartRate = viewModel.validateHeartRateOnSubmit(viewModel.maxHeartRate)
                } else if oldFocus == .caloriesBurned {
                    viewModel.caloriesBurned = viewModel.validateCaloriesOnSubmit(viewModel.caloriesBurned)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
        }

    private var permanentHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") {
                    viewModel.cleanupVideoFiles()
                    showingWorkoutForm = false
                }
                .font(.montserratRegular)
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Spacer()

                Text("Add Workout")
                    .font(.montserratSemiBold(size: 18))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Spacer()

                Button(action: {
                    Task {
                        await saveWorkout()
                    }
                }) {
                    if viewModel.isUploading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Save")
                    }
                }
                .font(.montserratSemiBold)
                .foregroundStyle(viewModel.isFormValid ? .accent : .gray)
                .disabled(!viewModel.isFormValid || viewModel.isUploading)
                .frame(width: 60)
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

    private func saveWorkout() async {
        do {
            let workout = try await viewModel.saveWorkout(to: modelContext)
            debugLog("✅ Successfully saved workout with \(workout.photos.count) photos")
            onWorkoutCompleted(workout)
        } catch {
            debugLog("❌ Error saving workout: \(error)")
            // Error is already set in viewModel
        }
    }

    private func syncDurationPickerWithViewModel() {
        durationPickerHours = Int(viewModel.durationHours) ?? 0
        durationPickerMinutes = Int(viewModel.durationMinutes) ?? 0
        durationPickerSeconds = Int(viewModel.durationSeconds) ?? 0
    }
}

enum WorkoutFormField: Hashable {
    case workoutName, durationHours, durationMinutes, durationSeconds, stepsValue, notes, caloriesBurned, avgHeartRate, maxHeartRate
}

#Preview {
    @Previewable @State var showForm = true
    WorkoutFormView(showingWorkoutForm: $showForm) { _ in }
        .modelContainer(for: [Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self], inMemory: true)
}

#Preview("Dark") {
    @Previewable @State var showForm = true
    WorkoutFormView(showingWorkoutForm: $showForm) { _ in }
        .modelContainer(for: [Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self], inMemory: true)
        .preferredColorScheme(.dark)
}
