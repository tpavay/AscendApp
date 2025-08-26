//
//  WorkoutFormView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import SwiftUI
import SwiftData

struct WorkoutFormView: View {
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
    
    @FocusState private var focusedField: WorkoutFormField?
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    private var isFormValid: Bool {
        !workoutName.isEmpty &&
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
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // Form Fields
                    VStack(spacing: 20) {
                        // Workout Name
                        formSection(title: "Workout Name") {
                            TextField("Enter workout name", text: $workoutName)
                                .focused($focusedField, equals: .workoutName)
                                .padding(12)
                                .background(Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                                )
                                .onSubmit {
                                    focusedField = nil
                                }
                                .onChange(of: workoutName) { _, newValue in
                                    // Cap at 50 characters
                                    if newValue.count > 50 {
                                        workoutName = String(newValue.prefix(50))
                                    }
                                }
                        }
                        
                        // Date & Time
                        formSection(title: "Date & Time") {
                            DatePicker("Workout Date", selection: $workoutDate, displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact)
                                .accentColor(.accent)
                        }
                        
                        // Duration
                        formSection(title: "Duration") {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Hours")
                                        .font(.montserratMedium)
                                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                                    TextField("0", text: $durationHours)
                                        .focused($focusedField, equals: .durationHours)
                                        .keyboardType(.numberPad)
                                        .padding(12)
                                        .background(Color.clear)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                                        )
                                        .onChange(of: durationHours) { _, newValue in
                                            // Cap hours at 999
                                            if let hours = Int(newValue), hours > 999 {
                                                durationHours = "999"
                                            }
                                        }
                                        .onSubmit {
                                            focusedField = .durationMinutes
                                        }
                                }
                                
                                Text(":")
                                    .font(.montserratBold(size: 24))
                                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                                    .padding(.top, 24)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Minutes")
                                        .font(.montserratMedium)
                                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                                    TextField("00", text: $durationMinutes)
                                        .focused($focusedField, equals: .durationMinutes)
                                        .keyboardType(.numberPad)
                                        .padding(12)
                                        .background(Color.clear)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                                        )
                                        .onChange(of: durationMinutes) { _, newValue in
                                            // Cap minutes at 59
                                            if let minutes = Int(newValue), minutes > 59 {
                                                durationMinutes = "59"
                                            }
                                        }
                                        .onSubmit {
                                            focusedField = .durationSeconds
                                        }
                                }
                                
                                Text(":")
                                    .font(.montserratBold(size: 24))
                                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                                    .padding(.top, 24)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Seconds")
                                        .font(.montserratMedium)
                                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                                    
                                    TextField("00", text: $durationSeconds)
                                        .focused($focusedField, equals: .durationSeconds)
                                        .keyboardType(.numberPad)
                                        .padding(12)
                                        .background(Color.clear)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                                        )
                                        .onChange(of: durationSeconds) { _, newValue in
                                            // Cap seconds at 59
                                            if let seconds = Int(newValue), seconds > 59 {
                                                durationSeconds = "59"
                                            }
                                        }
                                        .onSubmit {
                                            focusedField = .metricValue
                                        }
                                }
                            }
                        }
                        
                        // Steps/Floors
                        formSection(title: settingsManager.preferredWorkoutMetric.displayName) {
                            VStack(alignment: .leading, spacing: 4) {
                                TextField("Enter \(settingsManager.preferredWorkoutMetric.unit)", text: $metricValue)
                                    .focused($focusedField, equals: .metricValue)
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
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text("Currently tracking: \(settingsManager.preferredWorkoutMetric.description)")
                                            .font(.montserratRegular(size: 12))
                                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                                        
                                        Button(action: {
                                            showingMetricTooltip = true
                                        }) {
                                            Image(systemName: "info.circle")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(.accent.opacity(0.8))
                                        }
                                        .buttonStyle(.plain)
                                        
                                        Spacer()
                                    }
                                    
                                    if settingsManager.preferredWorkoutMetric == .steps {
                                        HStack(spacing: 6) {
                                            Text("Step height: \(String(format: "%.1f", settingsManager.stepHeight)) \(settingsManager.measurementSystem.stepHeightAbbreviation)")
                                                .font(.montserratRegular(size: 11))
                                                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray.opacity(0.8))
                                            
                                            Text("•")
                                                .font(.montserratRegular(size: 11))
                                                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray.opacity(0.8))
                                            
                                            Text("\(settingsManager.stepsPerFloor) steps per floor")
                                                .font(.montserratRegular(size: 11))
                                                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray.opacity(0.8))
                                            
                                            Spacer()
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Notes (Optional)
                        formSection(title: "Notes (Optional)") {
                            TextField("Add any notes about your workout...", text: $notes, axis: .vertical)
                                .focused($focusedField, equals: .notes)
                                .padding(12)
                                .background(Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                                )
                                .lineLimit(3...6)
                        }
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
            .themedBackground()
            .navigationTitle("New Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.clear, for: .navigationBar)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveWorkout()
                    }
                    .foregroundStyle(isFormValid ? .accent : .gray)
                    .disabled(!isFormValid)
                }
            }
        }
        .sheet(isPresented: $showingMetricTooltip) {
            MetricTooltipView()
                .presentationDetents([.fraction(0.40)])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            if workoutName.isEmpty {
                workoutName = generateDefaultWorkoutName()
            }
        }
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
        
        let workout = Workout(
            name: workoutName,
            date: workoutDate,
            duration: totalDuration,
            steps: settingsManager.preferredWorkoutMetric == .steps ? value : nil,
            floors: settingsManager.preferredWorkoutMetric == .floors ? value : nil,
            notes: notes
        )
        
        print("🔍 Created workout: \(workout.name)")
        modelContext.insert(workout)
        print("🔍 Inserted workout into context")
        
        do {
            try modelContext.save()
            print("✅ Successfully saved workout")
            dismiss()
        } catch {
            print("❌ Error saving workout: \(error)")
        }
    }
}

enum WorkoutFormField: Hashable {
    case workoutName, durationHours, durationMinutes, durationSeconds, metricValue, notes
}

#Preview {
    WorkoutFormView()
        .modelContainer(for: Workout.self, inMemory: true)
}

#Preview("Dark") {
    WorkoutFormView()
        .modelContainer(for: Workout.self, inMemory: true)
        .preferredColorScheme(.dark)
}
