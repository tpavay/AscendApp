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
    @Environment(AuthenticationViewModel.self) private var authVM
    @State private var themeManager = ThemeManager.shared
    @State private var importCoordinator = WorkoutImportCoordinator.shared
    @State private var settingsManager = SettingsManager.shared
    @State private var filterState = WorkoutListFilterState()

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
    @State private var isDeleting = false
    @State private var isCancelling = false
    @State private var deleteTask: Task<Void, Never>? = nil

    @State private var showingEntrySelection = false

    private var filteredWorkouts: [Workout] {
        let filtered = filterState.applyFilters(to: workouts)
        return filterState.applySorting(to: filtered, preferredMetric: settingsManager.preferredWorkoutMetric)
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
                    effectiveColorScheme: effectiveColorScheme,
                    pendingImportCount: importCoordinator.attentionCount,
                    workouts: workouts,
                    filterState: filterState,
                    onCancelDelete: exitDeleteMode,
                    onImportTapped: handleImportTapped,
                    onEnterDeleteMode: enterDeleteMode
                )

                // Workout count
                if !workouts.isEmpty {
                    if isInDeleteMode {
                        Text("\(selectedWorkouts.count) Selected")
                            .font(.montserratMedium(size: 13))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    } else {
                        Text("Showing \(filteredWorkouts.count) workout\(filteredWorkouts.count == 1 ? "" : "s")")
                            .font(.montserratMedium(size: 13))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }
                }

                if workouts.isEmpty {
                    WorkoutListEmptyStateView(
                        effectiveColorScheme: effectiveColorScheme
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
            .safeAreaInset(edge: .bottom) {
                if isInDeleteMode && !workouts.isEmpty {
                    deleteActionBar
                }
            }
            .navigationBarHidden(true)
            .overlay(alignment: .bottomTrailing) {
                if !isInDeleteMode {
                    // Floating Action Button
                    Button(action: {
                        showingEntrySelection = true
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
            }
            .sheet(isPresented: $showingEntrySelection) {
                WorkoutEntrySelectionView(
                    onManualEntry: {
                        showingEntrySelection = false
                        Task {
                            try await Task.sleep(for: .milliseconds(300))
                            showingWorkoutForm = true
                        }
                    },
                    onImportWorkouts: {
                        showingEntrySelection = false
                        Task {
                            try await Task.sleep(for: .milliseconds(300))
                            handleImportTapped()
                        }
                    },
                    pendingImportCount: importCoordinator.attentionCount
                )
                .appSheetStyle(.fitted())
            }
            .sheet(isPresented: $showingWorkoutForm) {
                WorkoutFormView(
                    showingWorkoutForm: $showingWorkoutForm,
                    onWorkoutCompleted: { workout in
                        print("🔍 WorkoutListView: onWorkoutCompleted called")
                        completedWorkout = workout

                        // Dismiss the form
                        showingWorkoutForm = false

                        // Then show completed view after a brief delay
                        Task {
                            try await Task.sleep(for: .milliseconds(300))
                            showingCompletedView = true
                            print("🔍 WorkoutListView: Set showingCompletedView = true")
                        }
                    }
                )
                .interactiveDismissDisabled()
            }
            .fullScreenCover(isPresented: $showingCompletedView) {
                if let workout = completedWorkout {
                    WorkoutShareCarouselView(
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
                    isLoading: isDeleting,
                    isCancelling: isCancelling,
                    onConfirm: {
                        // Guard against double-starting
                        guard deleteTask == nil else { return }
                        deleteTask = Task {
                            await deleteSelectedWorkouts()
                            deleteTask = nil
                        }
                    },
                    onCancel: {
                        if isDeleting {
                            // Cancel in-flight deletion
                            isCancelling = true
                            deleteTask?.cancel()
                            deleteTask = nil
                            isDeleting = false
                            isCancelling = false
                        }
                        showingDeleteConfirmation = false
                    }
                )
                .interactiveDismissDisabled(isDeleting || isCancelling)
                .onDisappear {
                    deleteTask?.cancel()
                    deleteTask = nil
                }
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
                importCoordinator.configure(modelContext: modelContext)
            }
        }
    }


    private var areAllWorkoutsSelected: Bool {
        let deletableWorkoutCount = workouts.filter { !$0.isLiveClimbAttemptWorkout }.count
        return deletableWorkoutCount > 0 && selectedWorkouts.count == deletableWorkoutCount
    }

    private var deleteActionBar: some View {
        SelectionActionBar(
            effectiveColorScheme: effectiveColorScheme,
            secondaryTitle: areAllWorkoutsSelected ? "Deselect All" : "Select All",
            onSecondaryTapped: toggleSelectAllWorkouts,
            isSecondaryDisabled: isDeleting || workouts.isEmpty,
            primaryTitle: "Delete Selected (\(selectedWorkouts.count))",
            onPrimaryTapped: handleDeleteTapped,
            isPrimaryDisabled: selectedWorkouts.isEmpty || isDeleting,
            primaryColor: .red
        )
    }

    private func toggleSelectAllWorkouts() {
        if areAllWorkoutsSelected {
            selectedWorkouts.removeAll()
        } else {
            selectedWorkouts = Set(workouts.filter { !$0.isLiveClimbAttemptWorkout }.map(\.id))
        }
    }

    private func handleDeleteTapped() {
        guard !selectedWorkouts.isEmpty else { return }

        let selectedWorkoutModels = workouts.filter { selectedWorkouts.contains($0.id) }
        let protectedWorkoutIds = selectedWorkoutModels
            .filter(\.isLiveClimbAttemptWorkout)
            .map(\.id)

        if !protectedWorkoutIds.isEmpty {
            selectedWorkouts.subtract(protectedWorkoutIds)
            deleteErrorMessage = "Live climb attempts are saved as competitive history and cannot be deleted from the workout log."
            showingDeleteError = true
        }

        if !selectedWorkouts.isEmpty {
            showingDeleteConfirmation = true
        }
    }

    private func handleImportTapped() {
        Task {
            let resolution = await importCoordinator.prepareImportInbox()
            if resolution == .showImportSheet {
                showingImportSheet = true
            }
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
        guard workouts.first(where: { $0.id == workoutId })?.isLiveClimbAttemptWorkout != true else {
            deleteErrorMessage = "Live climb attempts are saved as competitive history and cannot be deleted from the workout log."
            showingDeleteError = true
            return
        }

        if selectedWorkouts.contains(workoutId) {
            selectedWorkouts.remove(workoutId)
        } else {
            selectedWorkouts.insert(workoutId)
        }
    }

    private func deleteSelectedWorkouts() async {
        await MainActor.run {
            isDeleting = true
        }

        let workoutsToDelete = workouts.filter {
            selectedWorkouts.contains($0.id) && !$0.isLiveClimbAttemptWorkout
        }

        guard !workoutsToDelete.isEmpty else {
            await MainActor.run {
                isDeleting = false
                showingDeleteConfirmation = false
                deleteErrorMessage = "Live climb attempts are saved as competitive history and cannot be deleted from the workout log."
                showingDeleteError = true
            }
            return
        }

        let remoteSyncUserId = workoutsToDelete.lazy.compactMap { workout in
            workout.ownerUserId ?? authVM.user?.uid
        }.first

        for workout in workoutsToDelete {
            await MediaUploadManager.shared.cancelUploads(
                for: workout.id,
                modelContext: modelContext
            )
        }

        // Delete photos from Firebase first - ALL must succeed
        let photoService = PhotoService()
        let allPhotos = workoutsToDelete.flatMap { $0.photos }

        if !allPhotos.isEmpty {
            do {
                try await photoService.deletePhotos(allPhotos)
            } catch let error as PhotoDeletionError {
                print("❌ Failed to delete photos: \(error)")
                await MainActor.run {
                    isDeleting = false
                    showingDeleteConfirmation = false
                    switch error {
                    case .partialFailure(let result):
                        deleteErrorMessage = "Failed to delete \(result.failedCount) photo(s) from cloud storage. Please check your internet connection and try again."
                    case .timeout:
                        deleteErrorMessage = "Photo deletion timed out. Please check your internet connection and try again."
                    case .allRetriesExhausted:
                        deleteErrorMessage = "Failed to delete photos after multiple attempts. Please try again later."
                    }
                    showingDeleteError = true
                    HapticsManager.shared.trigger(.error)
                }
                return // Don't delete any workouts
            } catch {
                print("❌ Failed to delete photos from Firebase: \(error)")
                await MainActor.run {
                    isDeleting = false
                    showingDeleteConfirmation = false
                    deleteErrorMessage = "Failed to delete photos from cloud storage. Please check your internet connection and try again."
                    showingDeleteError = true
                    HapticsManager.shared.trigger(.error)
                }
                return // Don't delete any workouts
            }
        }

        // Only delete workouts if ALL photo deletions succeeded
        var shouldProcessRemoteDeletion = false
        do {
            let didQueueRemoteDeletion = try WorkoutSyncCoordinator.shared.enqueuePendingDeletions(
                for: workoutsToDelete,
                fallbackUserId: authVM.user?.uid,
                modelContext: modelContext
            )
            let deletedSnapshots = workoutsToDelete.map(LeaderboardWorkoutSnapshot.init(workout:))
            for workout in workoutsToDelete {
                modelContext.delete(workout)
            }
            try modelContext.save()
            shouldProcessRemoteDeletion = didQueueRemoteDeletion

            // Recalculate PRs and leaderboard stats after deletion
            try WorkoutMutationHandler.shared.workoutsDidChange(
                modelContext: modelContext,
                mutation: .deleted(deletedSnapshots)
            )

            if shouldProcessRemoteDeletion, let remoteSyncUserId {
                Task { @MainActor in
                    await WorkoutSyncCoordinator.shared.processPendingWorkouts(
                        modelContext: modelContext,
                        currentUserId: remoteSyncUserId
                    )
                }
            }

            await MainActor.run {
                isDeleting = false
                showingDeleteConfirmation = false
                HapticsManager.shared.trigger(.success)
                exitDeleteMode()
            }
        } catch {
            print("❌ Error deleting workouts: \(error)")

            if shouldProcessRemoteDeletion, let remoteSyncUserId {
                Task { @MainActor in
                    await WorkoutSyncCoordinator.shared.processPendingWorkouts(
                        modelContext: modelContext,
                        currentUserId: remoteSyncUserId
                    )
                }
            }

            await MainActor.run {
                isDeleting = false
                showingDeleteConfirmation = false
                deleteErrorMessage = "Failed to delete workouts from local storage. Please try again."
                showingDeleteError = true
                HapticsManager.shared.trigger(.error)
            }
        }
    }
}

#Preview {
    NavigationStack {
        WorkoutListView()
    }
    .modelContainer(for: [Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self], inMemory: true)
}
