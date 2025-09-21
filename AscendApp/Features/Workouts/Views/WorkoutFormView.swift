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

    @State private var selectedItems: [PhotosPickerItem] = []

    // Health Metrics
    @State private var showHealthMetrics = false
    @State private var avgHeartRate: String = ""
    @State private var maxHeartRate: String = ""
    @State private var caloriesBurned: String = ""
    @State private var durationFormatted: String = ""
    @State private var showingDatePicker = false
    @State private var effortRating: Double? = nil
    @State private var showingEffortRating = false
    
    @FocusState private var focusedField: WorkoutFormField?
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    private var isFormValid: Bool {
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
        
        return basicValidation && durationValid && avgHRValid && maxHRValid && caloriesValid
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
            DateTimePickerView(selectedDate: $workoutDate)
                .presentationDetents([.height(400)])
        }
        .sheet(isPresented: $showingEffortRating) {
            EffortRatingView(effortRating: $effortRating)
                .presentationDetents([.fraction(0.4)])
        }
        .onAppear {
            if workoutName.isEmpty {
                workoutName = generateDefaultWorkoutName()
            }
        }
    }
    
    private var workoutInfoCard: some View {
        VStack(spacing: 16) {
            // Workout Name
            TextField(generateDefaultWorkoutName(), text: $workoutName)
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
                .onChange(of: workoutName) { _, newValue in
                    if newValue.count > 50 {
                        workoutName = String(newValue.prefix(50))
                    }
                }
            
            // Description
            TextField("Add an optional description describing your workout", text: $notes, axis: .vertical)
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

            PhotoGalleryView(selectedPhotos: $selectedItems)

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
                    
                    Text(formatWorkoutDateTime())
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
                
                TextField("00:00:00", text: $durationFormatted)
                    .focused($focusedField, equals: .durationMinutes)
                    .keyboardType(.numberPad)
                    .font(.montserratRegular(size: 16))
                    .onChange(of: durationFormatted) { _, newValue in
                        formatDurationInput(newValue)
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
                TextField("Enter \(settingsManager.preferredWorkoutMetric.unit)", text: $metricValue)
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
                    Text(effortRatingDisplayText())
                        .font(.montserratRegular(size: 16))
                        .foregroundStyle(effortRating == nil ? .gray : (effectiveColorScheme == .dark ? .white : .black))
                    
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
                        TextField("Average heart rate (BPM)", text: $avgHeartRate)
                            .focused($focusedField, equals: .avgHeartRate)
                            .keyboardType(.numberPad)
                            .font(.montserratRegular(size: 16))
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                            )
                            .onChange(of: avgHeartRate) { _, newValue in
                                avgHeartRate = filterNumericInput(newValue)
                            }
                            .onSubmit { 
                                validateHeartRateOnSubmit($avgHeartRate)
                                focusedField = .maxHeartRate 
                            }
                        
                        // Maximum Heart Rate
                        TextField("Maximum heart rate (BPM)", text: $maxHeartRate)
                            .focused($focusedField, equals: .maxHeartRate)
                            .keyboardType(.numberPad)
                            .font(.montserratRegular(size: 16))
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                            )
                            .onChange(of: maxHeartRate) { _, newValue in
                                maxHeartRate = filterNumericInput(newValue)
                            }
                            .onSubmit { 
                                validateHeartRateOnSubmit($maxHeartRate)
                                focusedField = .caloriesBurned 
                            }
                        
                        // Calories Burned
                        TextField("Calories burned", text: $caloriesBurned)
                            .focused($focusedField, equals: .caloriesBurned)
                            .keyboardType(.numberPad)
                            .font(.montserratRegular(size: 16))
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                            )
                            .onChange(of: caloriesBurned) { _, newValue in
                                caloriesBurned = filterNumericInput(newValue)
                            }
                            .onSubmit { 
                                validateCaloriesOnSubmit()
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
                    validateHeartRateOnSubmit($avgHeartRate)
                } else if oldFocus == .maxHeartRate {
                    validateHeartRateOnSubmit($maxHeartRate)
                } else if oldFocus == .caloriesBurned {
                    validateCaloriesOnSubmit()
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
                    saveWorkout()
                }
                .font(.montserratSemiBold)
                .foregroundStyle(isFormValid ? .accent : .gray)
                .disabled(!isFormValid)
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
    
    private func formSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.montserratSemiBold)
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

            content()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                )
        )
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

    private func saveWorkout() {
        print("🔍 Save workout called")
        print("🔍 Form valid: \(isFormValid)")
        print("🔍 Workout name: '\(workoutName)'")
        print("🔍 Duration minutes: '\(durationMinutes)'")
        print("🔍 Duration seconds: '\(durationSeconds)'")
        print("🔍 Metric value: '\(metricValue)'")

        guard let minutes = Int(durationMinutes),
              let seconds = Int(durationSeconds),
              let value = Int(metricValue) else {
            print("❌ Guard failed - invalid number conversion")
            return
        }

        let hours = Int(durationHours) ?? 0
        let totalDuration = TimeInterval(hours * 3600 + minutes * 60 + seconds)

        // Convert health metrics, only include if values entered
        let avgHR = !avgHeartRate.isEmpty ? Int(avgHeartRate) : nil
        let maxHR = !maxHeartRate.isEmpty ? Int(maxHeartRate) : nil
        let calories = !caloriesBurned.isEmpty ? Int(caloriesBurned) : nil

        let workout = Workout(
            name: workoutName,
            date: workoutDate,
            duration: totalDuration,
            steps: settingsManager.preferredWorkoutMetric == .steps ? value : nil,
            floors: settingsManager.preferredWorkoutMetric == .floors ? value : nil,
            notes: notes,
            avgHeartRate: avgHR,
            maxHeartRate: maxHR,
            caloriesBurned: calories,
            effortRating: effortRating,
            source: .manual,
            deviceModel: UIDevice.current.model
        )

        print("🔍 Created workout: \(workout.name)")
        modelContext.insert(workout)
        print("🔍 Inserted workout into context")

        do {
            try modelContext.save()
            print("✅ Successfully saved workout")
            print("🔍 About to call onWorkoutCompleted")

            // Call the completion handler to show completed view
            onWorkoutCompleted(workout)
            print("🔍 Called onWorkoutCompleted")
        } catch {
            print("❌ Error saving workout: \(error)")
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

