//
//  WorkoutFormView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

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
    
    // Health Metrics
    @State private var showHealthMetrics = false
    @State private var avgHeartRate: Int = 120
    @State private var maxHeartRate: Int = 160
    @State private var caloriesBurned: String = ""
    @State private var durationFormatted: String = ""
    @State private var showingDatePicker = false
    
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
        
        // Validate calories if provided
        let caloriesValid = caloriesBurned.isEmpty || (Int(caloriesBurned) != nil && (Int(caloriesBurned) ?? 0) > 0)
        
        return basicValidation && durationValid && caloriesValid
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
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingDatePicker) {
            DateTimePickerView(selectedDate: $workoutDate)
                .presentationDetents([.fraction(0.4)])
                .presentationDragIndicator(.visible)
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
        }
    }
    
    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 20) {
                    workoutInfoCard
                        
                        // Health Metrics (Expandable)
                        VStack(alignment: .leading, spacing: 12) {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showHealthMetrics.toggle()
                                }
                            }) {
                                HStack {
                                    Text("Health Metrics (Optional)")
                                        .font(.montserratSemiBold)
                                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                                    
                                    Spacer()
                                    
                                    Image(systemName: showHealthMetrics ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.accent)
                                        .rotationEffect(.degrees(showHealthMetrics ? 0 : 0))
                                }
                            }
                            .buttonStyle(.plain)
                            
                            if showHealthMetrics {
                                VStack(spacing: 16) {
                                    // Heart Rate Section
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("Heart Rate (BPM)")
                                            .font(.montserratMedium)
                                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                                        
                                        HStack(spacing: 16) {
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text("Average")
                                                    .font(.montserratRegular(size: 14))
                                                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .gray)
                                                
                                                Picker("Average HR", selection: $avgHeartRate) {
                                                    ForEach(60...220, id: \.self) { value in
                                                        Text("\(value)").tag(value)
                                                    }
                                                }
                                                .pickerStyle(.wheel)
                                                .frame(height: 80)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                                                )
                                            }
                                            
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text("Maximum")
                                                    .font(.montserratRegular(size: 14))
                                                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .gray)
                                                
                                                Picker("Max HR", selection: $maxHeartRate) {
                                                    ForEach(60...220, id: \.self) { value in
                                                        Text("\(value)").tag(value)
                                                    }
                                                }
                                                .pickerStyle(.wheel)
                                                .frame(height: 80)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                                                )
                                            }
                                        }
                                    }
                                    
                                    // Calories Section
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Calories Burned")
                                            .font(.montserratMedium)
                                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                                        
                                        TextField("Enter calories", text: $caloriesBurned)
                                            .focused($focusedField, equals: .caloriesBurned)
                                            .keyboardType(.numberPad)
                                            .padding(12)
                                            .background(Color.clear)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                                            )
                                            .onSubmit {
                                                focusedField = .notes
                                            }
                                    }
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }
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
                    
                    Spacer(minLength: 40)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
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
    
    private func formatWorkoutDateTime() -> String {
        let calendar = Calendar.current
        let now = Date()
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

        // Convert health metrics, only include if health section was expanded and values entered
        let avgHR = showHealthMetrics ? avgHeartRate : nil
        let maxHR = showHealthMetrics ? maxHeartRate : nil
        let calories = showHealthMetrics && !caloriesBurned.isEmpty ? Int(caloriesBurned) : nil

        let workout = Workout(
            name: workoutName,
            date: workoutDate,
            duration: totalDuration,
            steps: settingsManager.preferredWorkoutMetric == .steps ? value : nil,
            floors: settingsManager.preferredWorkoutMetric == .floors ? value : nil,
            notes: notes,
            avgHeartRate: avgHR,
            maxHeartRate: maxHR,
            caloriesBurned: calories
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
    case workoutName, durationHours, durationMinutes, durationSeconds, metricValue, notes, caloriesBurned
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct DateTimePickerView: View {
    @Binding var selectedDate: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var tempDate: Date
    
    init(selectedDate: Binding<Date>) {
        self._selectedDate = selectedDate
        self._tempDate = State(initialValue: selectedDate.wrappedValue)
    }
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Handle bar
            RoundedRectangle(cornerRadius: 2.5)
                .fill(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
            
            VStack(spacing: 16) {
                Text("Select Date & Time")
                    .font(.montserratSemiBold(size: 18))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                DatePicker("", selection: $tempDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.wheel)
                    .accentColor(.accent)
                    .labelsHidden()
                
                HStack(spacing: 12) {
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Cancel")
                            .font(.montserratSemiBold)
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                            )
                    }
                    
                    Button(action: {
                        selectedDate = tempDate
                        dismiss()
                    }) {
                        Text("Done")
                            .font(.montserratSemiBold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.accent)
                            )
                    }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            
            Spacer()
        }
        .themedBackground()
    }
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
