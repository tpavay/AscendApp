//
//  DailyWorkoutDetailView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/28/25.
//

import SwiftUI
import SwiftData

struct DailyWorkoutDetailView: View {
    let date: Date
    let workouts: [Workout]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    private var sortedWorkouts: [Workout] {
        workouts.sorted { $0.date < $1.date }
    }
    
    private var totalDuration: TimeInterval {
        sortedWorkouts.reduce(0) { $0 + $1.duration }
    }
    
    private var totalSteps: Int? {
        let steps = sortedWorkouts.compactMap { $0.steps }
        return steps.isEmpty ? nil : steps.reduce(0, +)
    }
    
    private var totalFloors: Int? {
        let floors = sortedWorkouts.compactMap { $0.floors }
        return floors.isEmpty ? nil : floors.reduce(0, +)
    }
    
    private var primaryMetricTotal: Int? {
        if settingsManager.preferredWorkoutMetric == .steps {
            return totalSteps
        } else {
            return totalFloors
        }
    }
    
    private var primaryMetricType: WorkoutMetric {
        settingsManager.preferredWorkoutMetric
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header with date and summary stats
                    headerSection
                    
                    // Workouts list
                    workoutsListSection
                    
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
                
                Text("Daily Workouts")
                    .font(.montserratSemiBold(size: 18))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Spacer()
                
                // Placeholder for symmetry
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.clear)
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
        VStack(spacing: 20) {
            // Date
            VStack(spacing: 8) {
                Text(formatWorkoutDate())
                    .font(.montserratBold(size: 24))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Text("\(sortedWorkouts.count) workout\(sortedWorkouts.count == 1 ? "" : "s")")
                    .font(.montserratRegular(size: 16))
                    .foregroundStyle(.accent)
            }
            .padding(.top, 80) // Account for custom header
            
            // Summary stats
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    // Total Duration
                    summaryStatCard(
                        icon: "stopwatch",
                        title: "Total Duration",
                        value: formatDuration(totalDuration),
                        iconColor: .blue
                    )
                    
                    // Primary Metric Total
                    if let metricTotal = primaryMetricTotal {
                        summaryStatCard(
                            icon: primaryMetricType == .steps ? "figure.stairs" : "building",
                            title: "Total \(primaryMetricType.displayName)",
                            value: "\(metricTotal)",
                            subtitle: primaryMetricType.unit,
                            iconColor: .accent
                        )
                    }
                }
            }
        }
    }
    
    private var workoutsListSection: some View {
        VStack(spacing: 16) {
            // Section header
            HStack {
                Text("Workouts")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                Spacer()
            }
            
            VStack(spacing: 12) {
                ForEach(sortedWorkouts) { workout in
                    NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                        WorkoutRowCard(workout: workout)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
    
    private func summaryStatCard(
        icon: String,
        title: String,
        value: String,
        subtitle: String? = nil,
        iconColor: Color = .accent
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(height: 24)
            
            VStack(spacing: 4) {
                Text(title)
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .multilineTextAlignment(.center)
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.montserratBold(size: 16))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.montserratRegular(size: 12))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                )
        )
    }
    
    private func formatWorkoutDate() -> String {
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            dateFormatter.dateFormat = "EEEE, MMMM d"
            // Add year if not current year
            if calendar.component(.year, from: date) != calendar.component(.year, from: Date()) {
                dateFormatter.dateFormat = "EEEE, MMMM d, yyyy"
            }
            return dateFormatter.string(from: date)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct WorkoutRowCard: View {
    let workout: Workout
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    private var workoutTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: workout.date)
    }
    
    private var workoutPeriod: String {
        let hour = Calendar.current.component(.hour, from: workout.date)
        switch hour {
        case 5..<12:
            return "Morning"
        case 12..<17:
            return "Afternoon"
        case 17..<21:
            return "Evening"
        default:
            return "Night"
        }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Time and period
            VStack(alignment: .leading, spacing: 4) {
                Text(workoutTime)
                    .font(.montserratBold(size: 16))
                    .foregroundStyle(.accent)
                
                Text("\(workoutPeriod) Workout")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
            }
            .frame(width: 80, alignment: .leading)
            
            // Workout details
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.name)
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    .lineLimit(1)
                
                HStack {
                    Text(workout.durationFormatted)
                        .font(.montserratMedium(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7))
                    
                    if let metricValue = workout.primaryMetricValue {
                        Text("•")
                            .font(.montserratMedium(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                        
                        Text("\(metricValue) \(workout.metricType.unit)")
                            .font(.montserratMedium(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7))
                    }
                }
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview
#Preview {
    let sampleWorkouts = [
        Workout(
            name: "Morning Stair Climb",
            date: Date(),
            duration: 1800, // 30 minutes
            steps: 2500,
            effortRating: 4.0
        ),
        Workout(
            name: "Evening Session",
            date: Calendar.current.date(byAdding: .hour, value: 8, to: Date()) ?? Date(),
            duration: 2400, // 40 minutes
            steps: 3000,
            effortRating: 3.0
        )
    ]
    
    DailyWorkoutDetailView(date: Date(), workouts: sampleWorkouts)
}