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
    @Environment(\.modelContext) private var modelContext
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared
    @State private var importService = WorkoutImportService.shared
    
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @State private var showingWorkoutForm = false
    @State private var showingCompletedView = false
    @State private var completedWorkout: Workout?
    @State private var isInDeleteMode = false
    @State private var selectedWorkouts: Set<UUID> = []
    @State private var showingDeleteConfirmation = false
    @State private var showingImportSheet = false
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Sticky Header
            stickyHeader
            
            if workouts.isEmpty {
                emptyStateView
            } else {
                workoutsList
            }
        }
        .themedBackground()
        .navigationBarHidden(true)
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
        .fullScreenCover(isPresented: $showingWorkoutForm) {
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
        .sheet(isPresented: $showingDeleteConfirmation) {
            DeleteWorkoutConfirmationView(
                selectedCount: selectedWorkouts.count,
                onConfirm: {
                    deleteSelectedWorkouts()
                    showingDeleteConfirmation = false
                },
                onCancel: {
                    showingDeleteConfirmation = false
                }
            )
            .presentationDetents([.height(200)])
        }
        .sheet(isPresented: $showingImportSheet) {
            WorkoutImportSheet()
        }
        .task {
            // Configure import service with model context
            importService.configure(modelContext: modelContext)
        }
    }
    
    private var stickyHeader: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isInDeleteMode ? "Select Workouts" : "Workouts")
                        .font(.montserratBold(size: 32))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    
                    if isInDeleteMode {
                        Button(action: {
                            if selectedWorkouts.count == workouts.count {
                                selectedWorkouts.removeAll()
                            } else {
                                selectedWorkouts = Set(workouts.map { $0.id })
                            }
                        }) {
                            Text(selectedWorkouts.count == workouts.count ? "Deselect All" : "Select All")
                                .font(.montserratMedium(size: 14))
                                .foregroundStyle(.accent)
                        }
                    }
                }
                
                Spacer()
                
                if !workouts.isEmpty {
                    if isInDeleteMode {
                        HStack(spacing: 16) {
                            Button("Cancel") {
                                exitDeleteMode()
                            }
                            .foregroundStyle(.accent)
                            .font(.montserratMedium(size: 16))
                            
                            Button("Delete") {
                                if !selectedWorkouts.isEmpty {
                                    showingDeleteConfirmation = true
                                }
                            }
                            .foregroundStyle(selectedWorkouts.isEmpty ? .gray : .red)
                            .font(.montserratMedium(size: 16))
                            .disabled(selectedWorkouts.isEmpty)
                        }
                    } else {
                        Menu {
                            Button(action: {
                                Task {
                                    await importService.checkForNewWorkouts()
                                    showingImportSheet = true
                                }
                            }) {
                                HStack {
                                    Label("Import Workouts", systemImage: "square.and.arrow.down")
                                    if importService.pendingWorkoutsCount > 0 {
                                        Text("(\(importService.pendingWorkoutsCount))")
                                            .font(.caption)
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            
                            Button(action: {
                                enterDeleteMode()
                            }) {
                                Label("Delete Workouts", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
            
            // Divider
            Rectangle()
                .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))
                .frame(height: 1)
        }
        .background(
            (effectiveColorScheme == .dark ? Color.jet : Color.white)
                .opacity(0.95)
        )
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
                
                Text("Start tracking your stair climbing sessions")
                    .font(.montserratRegular(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: {
                Task {
                    await importService.checkForNewWorkouts()
                    showingImportSheet = true
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 16, weight: .medium))
                    Text("Import Workouts")
                        .font(.montserratMedium(size: 16))
                    if importService.pendingWorkoutsCount > 0 {
                        Text("(\(importService.pendingWorkoutsCount))")
                            .font(.caption)
                            .foregroundStyle(.white)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.accent)
                )
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .padding(20)
    }
    
    private var workoutsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(workouts) { workout in
                    HStack(spacing: 12) {
                        if isInDeleteMode {
                            Button(action: {
                                toggleWorkoutSelection(workout.id)
                            }) {
                                Image(systemName: selectedWorkouts.contains(workout.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(selectedWorkouts.contains(workout.id) ? .accent : .gray)
                            }
                        }
                        
                        if isInDeleteMode {
                            WorkoutRowView(workout: workout)
                                .onTapGesture {
                                    toggleWorkoutSelection(workout.id)
                                }
                        } else {
                            NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                                WorkoutRowView(workout: workout)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
    
    private func enterDeleteMode() {
        isInDeleteMode = true
        selectedWorkouts.removeAll()
    }
    
    private func exitDeleteMode() {
        isInDeleteMode = false
        selectedWorkouts.removeAll()
    }
    
    private func toggleWorkoutSelection(_ workoutId: UUID) {
        if selectedWorkouts.contains(workoutId) {
            selectedWorkouts.remove(workoutId)
        } else {
            selectedWorkouts.insert(workoutId)
        }
    }
    
    private func deleteSelectedWorkouts() {
        let workoutsToDelete = workouts.filter { selectedWorkouts.contains($0.id) }
        for workout in workoutsToDelete {
            modelContext.delete(workout)
        }
        exitDeleteMode()
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
                    
                    Text(workout.date.formatted(.dateTime.year()))
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    
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
