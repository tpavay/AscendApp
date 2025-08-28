//
//  WorkoutDetailView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/28/25.
//

import SwiftUI

struct WorkoutDetailView: View {
    let workout: Workout
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared
    @State private var showingEditWorkout = false
    @State private var showingDeleteConfirmation = false
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header with workout name and date
                    headerSection
                    
                    // Workout Details
                    workoutDetailsSection
                    
                    // Heart Rate Chart (if heart rate data is available)
                    if !workout.heartRateTimeSeries.isEmpty {
                        HeartRateChartView(
                            heartRateData: workout.heartRateTimeSeries,
                            workoutStartTime: workout.date,
                            workoutDuration: workout.duration
                        )
                    }
                    
                    // Calories and METs (if available and not already shown)
                    if workout.caloriesBurned != nil || workout.averageMETs != nil {
                        caloriesSection
                    }
                    
                    // Notes (if available)
                    if !workout.notes.isEmpty {
                        notesSection
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .themedBackground()
            .navigationBarHidden(true)
            .overlay(
                // Custom header bar
                VStack {
                    customHeader
                    Spacer()
                }
            )
            .fullScreenCover(isPresented: $showingEditWorkout) {
                EditWorkoutView(
                    workout: workout,
                    showingEditWorkout: $showingEditWorkout
                )
            }
            .sheet(isPresented: $showingDeleteConfirmation) {
                SingleWorkoutDeleteConfirmationView(
                    workout: workout,
                    onConfirm: {
                        deleteWorkout()
                        showingDeleteConfirmation = false
                    },
                    onCancel: {
                        showingDeleteConfirmation = false
                    }
                )
                .presentationDetents([.height(200)])
            }
        }
    }
    
    private var customHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.accent)
                }
                
                Spacer()
                
                Text("Workout Details")
                    .font(.montserratSemiBold(size: 18))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Spacer()
                
                Menu {
                    Button(action: {
                        showingEditWorkout = true
                    }) {
                        Label("Edit Workout", systemImage: "pencil")
                    }
                    
                    Button(role: .destructive, action: {
                        showingDeleteConfirmation = true
                    }) {
                        Label("Delete Workout", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
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
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Workout name
            Text(workout.name)
                .font(.montserratBold(size: 24))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                .multilineTextAlignment(.center)
            
            // Date & time
            VStack(spacing: 4) {
                Text(formatWorkoutDateTime())
                    .font(.montserratRegular(size: 16))
                    .foregroundStyle(.accent)
            }
        }
        .padding(.top, 80) // Account for custom header
    }
    
    private var workoutDetailsSection: some View {
        VStack(spacing: 16) {
            // Section header
            HStack {
                Text("Workout Summary")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                Spacer()
            }
            
            VStack(spacing: 16) {
                // Square grid for main metrics
                if workout.avgHeartRate != nil || workout.maxHeartRate != nil {
                    // Show duration, steps/floors, avg HR, max HR in square
                    squareMetricsGrid
                    
                    // Show pace and vertical climb below
                    additionalMetrics
                } else {
                    // Show duration, steps/floors, pace, vertical climb in square
                    fullWorkoutMetricsGrid
                }
                
                // Effort rating (if available)
                if let effortRating = workout.effortRating {
                    statCard(
                        icon: "bolt.fill",
                        title: "Effort Rating",
                        value: "\(Int(effortRating))/5",
                        subtitle: effortDescription(for: effortRating),
                        iconColor: .orange
                    )
                }
            }
        }
    }
    
    private var squareMetricsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            // Duration
            gridStatCard(
                icon: "stopwatch",
                title: "Duration",
                value: workout.durationFormatted
            )
            
            // Primary metric (Steps or Floors)
            if let metricValue = workout.primaryMetricValue {
                gridStatCard(
                    icon: workout.metricType == .steps ? "figure.stairs" : "building",
                    title: workout.metricType.displayName,
                    value: "\(metricValue)"
                )
            } else {
                // Empty placeholder
                gridStatCard(icon: "minus", title: "No Data", value: "—")
            }
            
            // Average Heart Rate
            if let avgHR = workout.avgHeartRate {
                gridStatCard(
                    icon: "heart.fill",
                    title: "Avg Heart Rate",
                    value: "\(avgHR)",
                    iconColor: .red
                )
            } else {
                gridStatCard(icon: "minus", title: "No Data", value: "—")
            }
            
            // Max Heart Rate
            if let maxHR = workout.maxHeartRate {
                gridStatCard(
                    icon: "heart.fill",
                    title: "Max Heart Rate",
                    value: "\(maxHR)",
                    iconColor: .red
                )
            } else {
                gridStatCard(icon: "minus", title: "No Data", value: "—")
            }
        }
    }
    
    private var fullWorkoutMetricsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            // Duration
            gridStatCard(
                icon: "stopwatch",
                title: "Duration",
                value: workout.durationFormatted
            )
            
            // Primary metric (Steps or Floors)
            if let metricValue = workout.primaryMetricValue {
                gridStatCard(
                    icon: workout.metricType == .steps ? "figure.stairs" : "building",
                    title: workout.metricType.displayName,
                    value: "\(metricValue)"
                )
            } else {
                gridStatCard(icon: "minus", title: "No Data", value: "—")
            }
            
            // Pace (if calculable)
            if let pace = workout.pace {
                gridStatCard(
                    icon: "speedometer",
                    title: "Pace",
                    value: String(format: "%.1f", pace)
                )
            } else {
                gridStatCard(icon: "minus", title: "No Data", value: "—")
            }
            
            // Vertical climb (for steps) or empty slot
            if let verticalClimb = workout.totalVerticalClimb(
                stepHeight: settingsManager.stepHeight,
                measurementSystem: settingsManager.measurementSystem
            ) {
                gridStatCard(
                    icon: "arrow.up",
                    title: "Vertical Climb",
                    value: String(format: "%.1f", verticalClimb)
                )
            } else {
                gridStatCard(icon: "minus", title: "No Data", value: "—")
            }
        }
    }
    
    private var additionalMetrics: some View {
        VStack(spacing: 16) {
            // Pace (if calculable)
            if let pace = workout.pace {
                statCard(
                    icon: "speedometer",
                    title: "Pace",
                    value: String(format: "%.1f", pace),
                    subtitle: "\(workout.metricType.unit)/min"
                )
            }
            
            // Vertical climb (for steps)
            if let verticalClimb = workout.totalVerticalClimb(
                stepHeight: settingsManager.stepHeight,
                measurementSystem: settingsManager.measurementSystem
            ) {
                statCard(
                    icon: "arrow.up",
                    title: "Vertical Climb",
                    value: String(format: "%.1f", verticalClimb),
                    subtitle: workout.verticalClimbUnit(measurementSystem: settingsManager.measurementSystem)
                )
            }
        }
    }
    
    private var caloriesSection: some View {
        VStack(spacing: 16) {
            // Section header
            HStack {
                Text("Additional Metrics")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                Spacer()
            }
            
            if let calories = workout.caloriesBurned {
                statCard(
                    icon: "flame.fill",
                    title: "Calories Burned",
                    value: "\(calories)",
                    subtitle: "calories",
                    iconColor: .orange
                )
            }
            
            if let averageMETs = workout.averageMETs {
                statCard(
                    icon: "bolt.circle.fill",
                    title: "Average METs",
                    value: String(format: "%.1f", averageMETs),
                    subtitle: "METs",
                    iconColor: .green
                )
            }
        }
    }
    
    private var notesSection: some View {
        VStack(spacing: 16) {
            // Section header
            HStack {
                Text("Notes")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(workout.notes)
                    .font(.montserratRegular(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
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
    }
    
    private func statCard(
        icon: String,
        title: String,
        value: String,
        subtitle: String? = nil,
        iconColor: Color = .accent,
        isProminent: Bool = false
    ) -> some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: isProminent ? 24 : 20, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: isProminent ? 32 : 28)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.montserratMedium(size: isProminent ? 16 : 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(.montserratBold(size: isProminent ? 28 : 20))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.montserratRegular(size: isProminent ? 16 : 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    }
                }
            }
            
            Spacer()
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
    
    private func gridStatCard(
        icon: String,
        title: String,
        value: String,
        iconColor: Color = .accent
    ) -> some View {
        VStack(spacing: 8) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(height: 24)
            
            // Content
            VStack(spacing: 4) {
                Text(title)
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                Text(value)
                    .font(.montserratBold(size: 18))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                )
        )
    }
    
    private func formatWorkoutDateTime() -> String {
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        
        if calendar.isDateInToday(workout.date) {
            return "Today at \(timeFormatter.string(from: workout.date))"
        } else if calendar.isDateInYesterday(workout.date) {
            return "Yesterday at \(timeFormatter.string(from: workout.date))"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"
            // Check if it's from this year
            if calendar.component(.year, from: workout.date) == calendar.component(.year, from: Date()) {
                return "\(dateFormatter.string(from: workout.date)) at \(timeFormatter.string(from: workout.date))"
            } else {
                dateFormatter.dateFormat = "MMM d, yyyy"
                return "\(dateFormatter.string(from: workout.date)) at \(timeFormatter.string(from: workout.date))"
            }
        }
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
    
    private func deleteWorkout() {
        modelContext.delete(workout)
        do {
            try modelContext.save()
            dismiss() // Navigate back to workout list
        } catch {
            print("❌ Error deleting workout: \(error)")
        }
    }
}

struct SingleWorkoutDeleteConfirmationView: View {
    let workout: Workout
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Delete Workout")
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Text("Are you sure you want to delete \"\(workout.name)\"? This action cannot be undone.")
                    .font(.montserratRegular(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .gray)
                    .multilineTextAlignment(.center)
            }
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1))
                )
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Button("Delete") {
                    onConfirm()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.red)
                )
                .foregroundStyle(.white)
            }
        }
        .padding(20)
        .themedBackground()
    }
}

// MARK: - Preview
#Preview {
    let sampleWorkout = Workout(
        name: "Morning Stair Climb",
        date: Date(),
        duration: 1800, // 30 minutes
        steps: 2500,
        floors: nil,
        notes: "Great morning workout! Felt really strong and maintained a good pace throughout the entire session.",
        avgHeartRate: 145,
        maxHeartRate: 165,
        caloriesBurned: 320,
        effortRating: 4.0
    )
    
    WorkoutDetailView(workout: sampleWorkout)
}

#Preview("No Health Metrics") {
    let sampleWorkout = Workout(
        name: "Evening Floors Session",
        date: Date().addingTimeInterval(-86400), // Yesterday
        duration: 2400, // 40 minutes
        steps: nil,
        floors: 85,
        notes: "",
        avgHeartRate: nil,
        maxHeartRate: nil,
        caloriesBurned: nil,
        effortRating: 3.0
    )
    
    WorkoutDetailView(workout: sampleWorkout)
        .preferredColorScheme(.dark)
}
