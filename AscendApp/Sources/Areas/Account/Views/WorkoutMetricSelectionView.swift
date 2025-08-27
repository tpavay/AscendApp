//
//  WorkoutMetricSelectionView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import SwiftUI

struct WorkoutMetricSelectionView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared
    
    @State private var stepsPerFloorText: String = ""
    @State private var showingStepHeightPicker = false
    @State private var showingStepsPerFloorPicker = false
    
    var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }
    
    // Step height ranges based on measurement system
    private var stepHeightRange: [Double] {
        let baseRange: [Double]
        switch settingsManager.measurementSystem {
        case .imperial:
            // 4.0 to 15.0 inches in 0.5 increments
            baseRange = Array(stride(from: 4.0, through: 15.0, by: 0.5))
        case .metric:
            // 10.0 to 38.0 cm in 0.5 increments  
            baseRange = Array(stride(from: 10.0, through: 38.0, by: 0.5))
        }
        
        // Ensure current step height is included in the range
        let currentHeight = settingsManager.stepHeight
        if !baseRange.contains(currentHeight) {
            return (baseRange + [currentHeight]).sorted()
        }
        
        return baseRange
    }
    
    // Steps per floor range
    private var stepsPerFloorRange: [Int] {
        let baseRange = Array(8...30) // 8 to 30 steps per floor
        
        // Ensure current steps per floor is included in the range
        let currentSteps = settingsManager.stepsPerFloor
        if !baseRange.contains(currentSteps) {
            return (baseRange + [currentSteps]).sorted()
        }
        
        return baseRange
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                Spacer()
                    .frame(height: 20)
                
                // Metric Options Section
                VStack(alignment: .leading, spacing: 16) {
                    // Section Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Workout Metric")
                            .font(.montserratSemiBold(size: 20))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                        
                        Text("Choose what you want to track during your workouts")
                            .font(.montserratRegular(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    }
                    
                    VStack(spacing: 12) {
                        ForEach(WorkoutMetric.allCases) { metric in
                            metricOptionRow(metric: metric)
                        }
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 20)
                
                // Step Configuration Section
                stepConfigurationSection()
                    .padding(.horizontal, 20)
                
                Spacer(minLength: 40)
            }
        }
        .themedBackground()
        .navigationTitle("Workout Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .onAppear {
            updateTextFields()
        }
        .onChange(of: settingsManager.measurementSystem) { _, _ in
            updateTextFields()
        }
        .sheet(isPresented: $showingStepHeightPicker) {
            stepHeightPickerSheet()
                .presentationDetents([.fraction(0.4)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingStepsPerFloorPicker) {
            stepsPerFloorPickerSheet()
                .presentationDetents([.fraction(0.4)])
                .presentationDragIndicator(.visible)
        }
    }
    
    private func metricOptionRow(metric: WorkoutMetric) -> some View {
        Button(action: {
            settingsManager.setPreferredMetric(metric)
        }) {
            HStack(spacing: 16) {
                // Metric Icon
                ZStack {
                    Circle()
                        .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.3) : .gray.opacity(0.1))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: metric == .steps ? "figure.walk" : "building.2")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.accent)
                }
                
                // Metric Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(metric.displayName)
                        .font(.montserratSemiBold)
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    
                    Text(metric.description)
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                }
                
                Spacer()
                
                // Selection Indicator
                ZStack {
                    Circle()
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if settingsManager.preferredWorkoutMetric == metric {
                        Circle()
                            .fill(.accent)
                            .frame(width: 16, height: 16)
                            .scaleEffect(settingsManager.preferredWorkoutMetric == metric ? 1.0 : 0.5)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: settingsManager.preferredWorkoutMetric)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.15) : .gray.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(settingsManager.preferredWorkoutMetric == metric ? .accent.opacity(0.5) : 
                                   (effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1)), 
                                   lineWidth: settingsManager.preferredWorkoutMetric == metric ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private func stepConfigurationSection() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Step Configuration")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Text("Configure your stair stepper settings for accurate climb calculations")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
            }
            
            VStack(spacing: 12) {
                // Step Height (Button to show picker)
                stepHeightRow()
                
                // Steps Per Floor
                stepsPerFloorRow()
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    private func stepInputRow(
        title: String,
        value: Binding<String>,
        unit: String,
        placeholder: String,
        description: String,
        onSave: @escaping () -> Void,
        onReset: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.montserratMedium)
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Spacer()
                
                Button(action: onReset) {
                    Text("Reset")
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.accent)
                }
            }
            
            HStack {
                TextField(placeholder, text: value)
                    .keyboardType(title.contains("Height") ? .decimalPad : .numberPad)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        onSave()
                    }
                    .onChange(of: value.wrappedValue) { _, _ in
                        onSave()
                    }
                
                Text(unit)
                    .font(.montserratRegular)
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .frame(minWidth: 50, alignment: .leading)
            }
            
            Text(description)
                .font(.montserratRegular(size: 12))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
        }
    }
    
    private func stepHeightRow() -> some View {
        HStack {
            HStack(spacing: 6) {
                Text("Step Height")
                    .font(.montserratMedium)
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                TooltipButton(
                    title: "Step Height",
                    content: "This is the height of each individual step on your stair stepper machine. Accurate step height helps calculate your total vertical climb distance."
                )
            }
            
            Spacer()
            
            Button(action: {
                showingStepHeightPicker = true
            }) {
                HStack(spacing: 4) {
                    Text(String(format: "%.1f", settingsManager.stepHeight))
                        .font(.montserratMedium)
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    
                    Text(settingsManager.measurementSystem.stepHeightUnit)
                        .font(.montserratRegular)
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    private func stepsPerFloorRow() -> some View {
        HStack {
            HStack(spacing: 6) {
                Text("Steps Per Floor")
                    .font(.montserratMedium)
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                TooltipButton(
                    title: "Steps Per Floor",
                    content: "The number of individual steps that equal one floor on your stair stepper. This helps convert between steps and floors for tracking your workouts."
                )
            }
            
            Spacer()
            
            Button(action: {
                showingStepsPerFloorPicker = true
            }) {
                HStack(spacing: 4) {
                    Text(String(settingsManager.stepsPerFloor))
                        .font(.montserratMedium)
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    
                    Text("steps")
                        .font(.montserratRegular)
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    private func stepHeightPickerSheet() -> some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("Step Height")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Text("Select the height of each step")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
            }
            
            // Picker
            HStack {
                Picker("Step Height", selection: $settingsManager.stepHeight) {
                    ForEach(stepHeightRange, id: \.self) { height in
                        Text(String(format: "%.1f", height))
                            .tag(height)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)
                
                Text(settingsManager.measurementSystem.stepHeightUnit)
                    .font(.montserratMedium)
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .frame(width: 80, alignment: .leading)
            }
            
            // Reset Button
            Button(action: {
                resetStepHeight()
                showingStepHeightPicker = false
            }) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .medium))
                    Text("Reset to Default (\(String(format: "%.1f", settingsManager.measurementSystem.defaultStepHeight)) \(settingsManager.measurementSystem.stepHeightAbbreviation))")
                        .font(.montserratMedium)
                }
                .foregroundStyle(.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .padding(20)
        .themedBackground()
    }
    
    private func stepsPerFloorPickerSheet() -> some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("Steps Per Floor")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Text("Select how many steps equal one floor")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
            }
            
            // Picker
            HStack {
                Picker("Steps Per Floor", selection: $settingsManager.stepsPerFloor) {
                    ForEach(stepsPerFloorRange, id: \.self) { steps in
                        Text(String(steps))
                            .tag(steps)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)
                
                Text("steps")
                    .font(.montserratMedium)
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .frame(width: 80, alignment: .leading)
            }
            
            // Reset Button
            Button(action: {
                resetStepsPerFloor()
                showingStepsPerFloorPicker = false
            }) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .medium))
                    Text("Reset to Default (\(settingsManager.measurementSystem.defaultStepsPerFloor) steps)")
                        .font(.montserratMedium)
                }
                .foregroundStyle(.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .padding(20)
        .themedBackground()
    }
    
    private func updateTextFields() {
        stepsPerFloorText = String(settingsManager.stepsPerFloor)
    }
    
    private func resetStepHeight() {
        let defaultHeight = settingsManager.measurementSystem.defaultStepHeight
        settingsManager.setStepHeight(defaultHeight)
    }
    
    private func resetStepsPerFloor() {
        let defaultSteps = settingsManager.measurementSystem.defaultStepsPerFloor
        stepsPerFloorText = String(defaultSteps)
        settingsManager.setStepsPerFloor(defaultSteps)
    }
}

#Preview("Light Theme") {
    NavigationStack {
        WorkoutMetricSelectionView()
    }
    .preferredColorScheme(.light)
}

#Preview("Dark Theme") {
    NavigationStack {
        WorkoutMetricSelectionView()
    }
    .preferredColorScheme(.dark)
}
