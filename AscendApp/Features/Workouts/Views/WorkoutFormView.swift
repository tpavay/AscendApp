//
//  WorkoutFormView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import PhotosUI
import SwiftUI
import SwiftData

struct WorkoutFormView: View {
    @Binding var showingWorkoutForm: Bool
    let onWorkoutCompleted: (Workout) -> Void

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
        .overlay {
            if viewModel.isUploading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Uploading photos...")
                        .font(.montserratMedium(size: 16))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
            }
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
                viewModel.workoutName = generateDefaultWorkoutName()
            }
        }
    }

    private var workoutInfoCard: some View {
        VStack(spacing: 16) {
            // Workout Name
            TextField(generateDefaultWorkoutName(), text: $viewModel.workoutName)
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
            TextField("Add an optional description describing your workout", text: $viewModel.notes, axis: .vertical)
                .focused($focusedField, equals: .notes)
                .font(.montserratRegular(size: 16))
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                )
                .lineLimit(3...6)
                .onSubmit {
                    focusedField = nil
                }

            PhotoGalleryView(selectedPhotos: $viewModel.selectedItems)

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
            HStack {
                Image(systemName: "clock")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.gray)

                TextField("00:00:00", text: $viewModel.durationFormatted)
                    .focused($focusedField, equals: .durationMinutes)
                    .keyboardType(.numberPad)
                    .font(.montserratRegular(size: 16))
                    .onChange(of: viewModel.durationFormatted) { _, newValue in
                        viewModel.formatDurationInput(newValue)
                    }
                    .onSubmit { focusedField = .metricValue }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
            )

            // Steps/Floors
            HStack {
                TextField("Enter \(settingsManager.preferredWorkoutMetric.unit)", text: $viewModel.metricValue)
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
        }

    private var permanentHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") {
                    showingWorkoutForm = false
                }
                .font(.montserratRegular)
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Spacer()

                Text("Add Workout")
                    .font(.montserratSemiBold(size: 18))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Spacer()

                Button("Save") {
                    Task {
                        await saveWorkout()
                    }
                }
                .font(.montserratSemiBold)
                .foregroundStyle(viewModel.isFormValid ? .accent : .gray)
                .disabled(!viewModel.isFormValid)
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

    private func generateDefaultWorkoutName() -> String {
        let hour = Calendar.current.component(.hour, from: Date())

        switch hour {
        case 5..<12:
            return "Morning Workout"
        case 12..<18:
            return "Afternoon Workout"
        default:
            return "Evening Workout"
        }
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