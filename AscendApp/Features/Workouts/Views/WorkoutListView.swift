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
    @State private var importService = WorkoutImportService.shared
    @StateObject private var filterState = WorkoutListFilterState()
    
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @State private var showingWorkoutForm = false
    @State private var showingCompletedView = false
    @State private var completedWorkout: Workout?
    @State private var isInDeleteMode = false
    @State private var selectedWorkouts: Set<UUID> = []
    @State private var showingDeleteConfirmation = false
    @State private var showingImportSheet = false
    @State private var showingDeleteError = false
    @State private var deleteErrorMessage = ""

    private var filteredWorkouts: [Workout] {
        filterState.applyFilters(to: workouts)
    }

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                WorkoutListHeaderView(
                    isInDeleteMode: isInDeleteMode,
                    totalCount: workouts.count,
                    selectedCount: selectedWorkouts.count,
                    allSelected: areAllWorkoutsSelected,
                    effectiveColorScheme: effectiveColorScheme,
                    pendingImportCount: importService.pendingWorkoutsCount,
                    canDelete: !selectedWorkouts.isEmpty,
                    onToggleSelectAll: toggleSelectAllWorkouts,
                    onCancelDelete: exitDeleteMode,
                    onDeleteTapped: handleDeleteTapped,
                    onImportTapped: handleImportTapped,
                    onEnterDeleteMode: enterDeleteMode
                ) {
                    WorkoutListSearchTriggerView(
                        filterState: filterState,
                        effectiveColorScheme: effectiveColorScheme
                    ) {
                        WorkoutFilterExplorerView(
                            workouts: workouts,
                            filterState: filterState
                        )
                    }
                }

                if workouts.isEmpty {
                    WorkoutListEmptyStateView(
                        effectiveColorScheme: effectiveColorScheme,
                        pendingImportCount: importService.pendingWorkoutsCount,
                        onImportTapped: handleImportTapped
                    )
                } else {
                    WorkoutResultsListView(
                        filteredWorkouts: filteredWorkouts,
                        isInDeleteMode: isInDeleteMode,
                        effectiveColorScheme: effectiveColorScheme,
                        selectedWorkouts: selectedWorkouts,
                        toggleSelection: toggleWorkoutSelection
                    )
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
                        Task {
                            await deleteSelectedWorkouts()
                        }
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
            .alert("Delete Failed", isPresented: $showingDeleteError) {
                Button("OK") {
                    showingDeleteError = false
                }
            } message: {
                Text(deleteErrorMessage)
            }
            .task {
                // Configure import service with model context
                importService.configure(modelContext: modelContext)
            }
        }
    }
    
    
    private var areAllWorkoutsSelected: Bool {
        !workouts.isEmpty && selectedWorkouts.count == workouts.count
    }
    
    private func toggleSelectAllWorkouts() {
        if areAllWorkoutsSelected {
            selectedWorkouts.removeAll()
        } else {
            selectedWorkouts = Set(workouts.map { $0.id })
        }
    }
    
    private func handleDeleteTapped() {
        if !selectedWorkouts.isEmpty {
            showingDeleteConfirmation = true
        }
    }
    
    private func handleImportTapped() {
        Task {
            await importService.checkForNewWorkouts()
            showingImportSheet = true
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
    
    private func deleteSelectedWorkouts() async {
        let workoutsToDelete = workouts.filter { selectedWorkouts.contains($0.id) }

        // Delete photos from Firebase first - ALL must succeed
        let photoService = PhotoService()
        do {
            for workout in workoutsToDelete {
                if !workout.photos.isEmpty {
                    try await photoService.deletePhotos(workout.photos)
                }
            }
        } catch {
            print("❌ Failed to delete photos from Firebase: \(error)")
            await MainActor.run {
                deleteErrorMessage = "Failed to delete photos from cloud storage. Please check your internet connection and try again."
                showingDeleteError = true
            }
            return // Don't delete any workouts
        }

        // Only delete workouts if ALL photo deletions succeeded
        do {
            for workout in workoutsToDelete {
                modelContext.delete(workout)
            }
            try modelContext.save()

            await MainActor.run {
                exitDeleteMode()
            }
        } catch {
            print("❌ Error deleting workouts: \(error)")
            await MainActor.run {
                deleteErrorMessage = "Failed to delete workouts from local storage. Please try again."
                showingDeleteError = true
            }
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
