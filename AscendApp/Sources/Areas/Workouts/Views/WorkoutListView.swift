//
//  WorkoutListView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import SwiftUI
import SwiftData

struct WorkoutListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared
    
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @State private var showingWorkoutForm = false
    @State private var showingCompletedView = false
    @State private var completedWorkout: Workout?
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if workouts.isEmpty {
                emptyStateView
            } else {
                workoutsList
            }
        }
        .themedBackground()
        .navigationTitle("Workouts")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .overlay(alignment: .bottomTrailing) {
            // Floating Action Button
            Button(action: {
                showingWorkoutForm = true
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(
                        Circle()
                            .fill(.accent)
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    )
            }
            .padding(20)
        }
        .sheet(isPresented: $showingWorkoutForm) {
            WorkoutFormView(
                showingWorkoutForm: $showingWorkoutForm,
                onWorkoutCompleted: { workout in
                    print("🔍 WorkoutListView: onWorkoutCompleted called")
                    completedWorkout = workout
                    
                    // Dismiss the form first
                    showingWorkoutForm = false
                    
                    // Then show completed view after a brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showingCompletedView = true
                        print("🔍 WorkoutListView: Set showingCompletedView = true")
                    }
                }
            )
        }
        .fullScreenCover(isPresented: $showingCompletedView) {
            if let workout = completedWorkout {
                WorkoutCompletedView(
                    workout: workout,
                    workoutCount: workouts.count,
                    onDismiss: {
                        showingCompletedView = false
                    }
                )
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "figure.stair.stepper")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(.accent)
            
            VStack(spacing: 8) {
                Text("No Workouts Yet")
                    .font(.montserratBold(size: 28))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Text("Start tracking your stairmaster sessions")
                    .font(.montserratRegular(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .multilineTextAlignment(.center)
            }
            
            
            Spacer()
        }
        .padding(20)
    }
    
    private var workoutsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(workouts) { workout in
                    WorkoutRowView(workout: workout)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
}

struct WorkoutRowView: View {
    let workout: Workout
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Workout Name (prominent)
            Text(workout.name)
                .font(.montserratBold(size: 18))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 16) {
                // Date
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.date.formatted(.dateTime.month().day()))
                        .font(.montserratBold(size: 16))
                        .foregroundStyle(.accent)
                    
                    Text(workout.date.formatted(.dateTime.hour().minute()))
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                }
                .frame(width: 60, alignment: .leading)
                
                // Workout Details
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(workout.primaryMetricValue ?? 0) \(workout.metricType.unit)")
                            .font(.montserratSemiBold)
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                        
                        Spacer()
                        
                        Text(workout.durationFormatted)
                            .font(.montserratMedium)
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7))
                    }
                    
                    if !workout.notes.isEmpty {
                        Text(workout.notes)
                            .font(.montserratRegular(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                            .lineLimit(2)
                    }
                }
            }
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

#Preview {
    NavigationStack {
        WorkoutListView()
    }
    .modelContainer(for: Workout.self, inMemory: true)
}