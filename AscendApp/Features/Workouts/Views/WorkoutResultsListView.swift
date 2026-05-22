//
//  WorkoutResultsListView.swift
//  AscendApp
//
//  Created by Codex on 3/14/24.
//

import SwiftData
import SwiftUI

struct WorkoutResultsListView: View {
    let filteredWorkouts: [Workout]
    let allWorkouts: [Workout]
    let isInDeleteMode: Bool
    let effectiveColorScheme: ColorScheme
    let selectedWorkouts: Set<UUID>
    let toggleSelection: (UUID) -> Void
    @Query(sort: \BestEffortCacheEntry.sortKey) private var bestEffortCacheEntries: [BestEffortCacheEntry]

    var body: some View {
        let primaryBestEffortsByWorkoutID = BestEffortCacheSnapshot(
            entries: bestEffortCacheEntries,
            workouts: allWorkouts
        )
        .primaryEffortsByWorkoutID()

        ScrollView {
            LazyVStack(spacing: 12) {
                if filteredWorkouts.isEmpty {
                    emptyResultsView
                }
                
                ForEach(filteredWorkouts) { workout in
                    HStack(spacing: 12) {
                        if isInDeleteMode {
                            selectionButton(for: workout.id)
                        }
                        
                        if isInDeleteMode {
                            Button { toggleSelection(workout.id) } label: {
                                WorkoutRowView(
                                    workout: workout,
                                    bestEffort: primaryBestEffortsByWorkoutID[workout.id]
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                                WorkoutRowView(
                                    workout: workout,
                                    bestEffort: primaryBestEffortsByWorkoutID[workout.id]
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 124)
        }
        .scrollIndicators(.hidden)
    }
    
    private var emptyResultsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.accent)
            
            Text("No workouts match your filters")
                .font(.montserratMedium(size: 16))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
    
    private func selectionButton(for workoutId: UUID) -> some View {
        Button(action: {
            toggleSelection(workoutId)
        }) {
            Image(systemName: selectedWorkouts.contains(workoutId) ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(selectedWorkouts.contains(workoutId) ? .accent : .gray)
        }
    }
}
