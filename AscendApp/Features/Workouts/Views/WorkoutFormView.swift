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
    let duration: TimeInterval
    let weightConfiguration: WeightConfiguration?
    let difficulty: Int?
}

struct WorkoutFormView: View {
    @Binding var showingWorkoutForm: Bool
    let onWorkoutCompleted: (Workout) -> Void
    var prefillResult: ConsoleScanResult? = nil
    var routinePrefill: RoutinePrefillData? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared

    // ViewModel handles all form logic and state
    @State private var viewModel = WorkoutFormViewModel()

    // UI-only state
    @State private var showingMetricTooltip = false
    @State private var showingDatePicker = false
    @State private var showingEffortRating = false
    @State private var showingDurationPicker = false
    @State private var durationPickerHours = 0
    @State private var durationPickerMinutes = 0
    @State private var durationPickerSeconds = 0

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
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    KeyboardDismissButton()
                }
            }
        }
        .sheet(isPresented: $showingMetricTooltip) {
            MetricTooltipView()
                .presentationDetents([.fraction(0.30)])
        }
        .sheet(isPresented: $showingDatePicker) {
            DateTimePickerView(selectedDate: $viewModel.workoutDate)
                .presentationDetents([.height(400)])
        }
        .sheet(isPresented: $showingEffortRating) {
            EffortRatingView(effortRating: $viewModel.effortRating)
                .presentationDetents([.fraction(0.4)])
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
            .presentationDetents([.height(340)])
            .interactiveDismissDisabled()
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
            // Apply prefill from console scan if provided
            if let result = prefillResult {
                viewModel.prefillFromScan(result)
            }
            // Apply prefill from routine completion if provided
            if let routine = routinePrefill {
                viewModel.prefillFromRoutine(
                    name: routine.name,
                    duration: routine.duration,
                    weightConfiguration: routine.weightConfiguration,
                    difficulty: routine.difficulty
                )
            }
        }
    }

    private var workoutInfoCard: some View {
        VStack(spacing: 16) {
            // Workout Name
            TextField(Workout.generateDefaultName(for: viewModel.workoutDate), text: $viewModel.workoutName)
                .focused($focusedField, equals: .workoutName)
                .font(.montserratRegular(size: 18))
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                )
                .onSubmit {
                    focusedField = .notes
                }
                .onChange(of: viewModel.workoutName) { _, newValue in
                    if newValue.count > 50 {
                        viewModel.workoutName = String(newValue.prefix(50))
                    }
                }

            // Description
            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.notes)
                    .focused($focusedField, equals: .notes)
                    .font(.montserratRegular(size: 16))
                    .frame(minHeight: 80, maxHeight: 150)
                    .scrollContentBackground(.hidden)
                    .background(.clear)

                if viewModel.notes.isEmpty {
                    Text("Add an optional description describing your workout")
                        .font(.montserratRegular(size: 16))
                        .foregroundStyle(.gray.opacity(0.6))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
            )

            PhotoGalleryView(
                selectedImages: $viewModel.selectedImages,
                highlightedSelectedItemId: Binding(
                    get: { viewModel.highlightedSelectedItemId },
                    set: { viewModel.highlightedSelectedItemId = $0 }
                )
            )

            // Section Header
            HStack {
                Text("Workout Details")
                    .font(.montserratSemiBold(size: 18))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Spacer()
            }
            .padding(.top, 8)

            // Custom Date/Time Display
            Button(action: {
                showingDatePicker = true
            }) {
                HStack {
                    Image(systemName: "calendar")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.gray)

                    Text(viewModel.formatWorkoutDateTime())
                        .font(.montserratRegular(size: 16))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.gray)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // Duration - Auto-formatting text input
            Button {
                syncDurationPickerWithViewModel()
                showingDurationPicker = true
            } label: {
                HStack {
                    Image(systemName: "clock")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.gray)

                    Text(viewModel.durationFormatted.isEmpty ? "00:00:00" : viewModel.durationFormatted)
                        .font(.montserratRegular(size: 16))
                        .foregroundStyle(viewModel.durationFormatted.isEmpty ? .gray : (effectiveColorScheme == .dark ? .white : .black))

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.gray)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // Steps/Floors
            HStack {
                TextField("Enter \(settingsManager.preferredWorkoutMetric.unit) (optional)", text: $viewModel.metricValue)
                    .focused($focusedField, equals: .metricValue)
                    .keyboardType(.numberPad)
                    .font(.montserratRegular(size: 16))
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                    )
                    .onSubmit { focusedField = nil }

                Button(action: {
                    showingMetricTooltip = true
                }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.accent)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            // Effort Rating (Optional)
            Button(action: {
                showingEffortRating = true
            }) {
                HStack {
                    Text(viewModel.effortRatingDisplayText())
                        .font(.montserratRegular(size: 16))
                        .foregroundStyle(viewModel.effortRating == nil ? .gray : (effectiveColorScheme == .dark ? .white : .black))

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.gray)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var scrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                VStack(spacing: 20) {
                    workoutInfoCard

                        // Health Metrics Section Header
                        HStack {
                            Text("Health Metrics (Optional)")
                                .font(.montserratSemiBold(size: 18))
                                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                            Spacer()
                        }
                        .padding(.top, 16)

                        // Average Heart Rate
                        TextField("Average heart rate (BPM)", text: $viewModel.avgHeartRate)
                            .focused($focusedField, equals: .avgHeartRate)
                            .keyboardType(.numberPad)
                            .font(.montserratRegular(size: 16))
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                            )
                            .onChange(of: viewModel.avgHeartRate) { _, newValue in
                                viewModel.avgHeartRate = viewModel.filterNumericInput(newValue)
                            }
                            .onSubmit {
                                viewModel.avgHeartRate = viewModel.validateHeartRateOnSubmit(viewModel.avgHeartRate)
                                focusedField = .maxHeartRate
                            }

                        // Maximum Heart Rate
                        TextField("Maximum heart rate (BPM)", text: $viewModel.maxHeartRate)
                            .focused($focusedField, equals: .maxHeartRate)
                            .keyboardType(.numberPad)
                            .font(.montserratRegular(size: 16))
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                            )
                            .onChange(of: viewModel.maxHeartRate) { _, newValue in
                                viewModel.maxHeartRate = viewModel.filterNumericInput(newValue)
                            }
                            .onSubmit {
                                viewModel.maxHeartRate = viewModel.validateHeartRateOnSubmit(viewModel.maxHeartRate)
                                focusedField = .caloriesBurned
                            }

                        // Calories Burned
                        TextField("Calories burned", text: $viewModel.caloriesBurned)
                            .focused($focusedField, equals: .caloriesBurned)
                            .keyboardType(.numberPad)
                            .font(.montserratRegular(size: 16))
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                            )
                            .onChange(of: viewModel.caloriesBurned) { _, newValue in
                                viewModel.caloriesBurned = viewModel.filterNumericInput(newValue)
                            }
                            .onSubmit {
                                viewModel.caloriesBurned = viewModel.validateCaloriesOnSubmit(viewModel.caloriesBurned)
                                focusedField = nil
                            }

                        // Weights Section Header
                        HStack {
                            Text("Weights Used (Optional)")
                                .font(.montserratSemiBold(size: 18))
                                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                            Spacer()
                        }
                        .padding(.top, 16)

                        WeightEntryView(
                            configuration: $viewModel.weightConfiguration,
                            measurementSystem: settingsManager.measurementSystem
                        )
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
            print("✅ Successfully saved workout with \(workout.photos.count) photos")
            onWorkoutCompleted(workout)
        } catch {
            print("❌ Error saving workout: \(error)")
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
    case workoutName, durationHours, durationMinutes, durationSeconds, metricValue, notes, caloriesBurned, avgHeartRate, maxHeartRate
}

#Preview {
    @Previewable @State var showForm = true
    WorkoutFormView(showingWorkoutForm: $showForm) { _ in }
        .modelContainer(for: Workout.self, inMemory: true)
}

#Preview("Dark") {
    @Previewable @State var showForm = true
    WorkoutFormView(showingWorkoutForm: $showForm) { _ in }
        .modelContainer(for: Workout.self, inMemory: true)
        .preferredColorScheme(.dark)
}
