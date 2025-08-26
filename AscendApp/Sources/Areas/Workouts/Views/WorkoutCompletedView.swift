//
//  WorkoutCompletedView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/26/25.
//

import SwiftUI
import SwiftData

struct WorkoutCompletedView: View {
    let workout: Workout
    let workoutCount: Int
    let onDismiss: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Achievement Header
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60, weight: .light))
                        .foregroundStyle(.green)
                    
                    VStack(spacing: 4) {
                        Text("Workout #\(workoutCount) Complete!")
                            .font(.montserratBold(size: 28))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                            .multilineTextAlignment(.center)
                        
                        Text("Great job on your stairmaster session!")
                            .font(.montserratRegular(size: 16))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 20)
                .padding(.horizontal, 20)
                
                Spacer(minLength: 40)
                
                // Combined Stats Card
                VStack(spacing: 20) {
                    // Duration
                    statRow(
                        title: "Duration",
                        value: workout.durationFormatted,
                        icon: "clock.fill",
                        color: .blue
                    )
                    
                    Divider()
                        .background(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))
                    
                    // Steps/Floors
                    statRow(
                        title: workout.metricType.displayName,
                        value: "\(workout.primaryMetricValue ?? 0)",
                        icon: workout.metricType == .steps ? "figure.walk" : "building.2",
                        color: .accent
                    )
                    
                    // Vertical Climb (only if steps)
                    if let verticalClimb = workout.totalVerticalClimb(
                        stepHeight: settingsManager.stepHeight,
                        measurementSystem: settingsManager.measurementSystem
                    ) {
                        Divider()
                            .background(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))
                        
                        statRow(
                            title: "Vertical Climb",
                            value: String(format: "%.1f %@", 
                                   verticalClimb,
                                   workout.verticalClimbUnit(measurementSystem: settingsManager.measurementSystem)),
                            icon: "mountain.2.fill",
                            color: .orange
                        )
                    }
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 20)
                
                Spacer(minLength: 40)
                
                // Done Button
                Button(action: {
                    onDismiss()
                }) {
                    Text("Done")
                        .font(.montserratSemiBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 55)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.accent)
                        )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .themedBackground()
    }
    
    private func statRow(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.montserratMedium)
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                
                Text(value)
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
            }
            
            Spacer()
        }
    }
}

#Preview {
    let workout = Workout(
        name: "Morning Workout",
        date: Date(),
        duration: 1800, // 30 minutes
        steps: 2400,
        floors: nil,
        notes: "Great session!"
    )
    
    return WorkoutCompletedView(workout: workout, workoutCount: 5, onDismiss: {})
}

#Preview("Dark") {
    let workout = Workout(
        name: "Evening Workout", 
        date: Date(),
        duration: 2400, // 40 minutes
        steps: nil,
        floors: 150,
        notes: ""
    )
    
    return WorkoutCompletedView(workout: workout, workoutCount: 12, onDismiss: {})
        .preferredColorScheme(.dark)
}
