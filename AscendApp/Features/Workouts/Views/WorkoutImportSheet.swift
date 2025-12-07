//
//  WorkoutImportSheet.swift
//  AscendApp
//
//  Created by Claude on 9/1/25.
//

import SwiftUI
import HealthKit

struct WorkoutImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var importService = WorkoutImportService.shared
    @State private var importingWorkoutId: UUID? = nil  // Currently importing single workout
    @State private var isImportingAll = false  // Bulk import in progress

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var unimportedCount: Int {
        importService.pendingWorkouts.filter { workout in
            !importService.isWorkoutImported(workout.uuid.uuidString)
        }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Content
                    if importService.pendingWorkouts.isEmpty {
                        emptyStateView
                    } else {
                        workoutListSection
                    }
                }
            }
            .navigationTitle("Import Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(.accent)
                }
            }
        }
        .themedBackground()
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.accent)

            Text("No New Workouts")
                .font(.montserratBold(size: 20))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

            Text("All your Apple Health workouts have already been imported.")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .padding(.top, 60)
    }

    // MARK: - Workout List Section

    private var workoutListSection: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                HStack {
                    Text("\(unimportedCount) NEW WORKOUTS")
                        .font(.montserratSemiBold(size: 12))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if isImportingAll {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if unimportedCount > 0 {
                        Button {
                            importAllWorkouts()
                        } label: {
                            Text("Import All")
                                .font(.montserratSemiBold(size: 14))
                                .foregroundStyle(.accent)
                        }
                        .disabled(importingWorkoutId != nil)
                    }
                }
                .padding(.horizontal, 20)

                Rectangle()
                    .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))
                    .frame(height: 1)
            }
            .padding(.bottom, 8)

            // Workout rows
            LazyVStack(spacing: 0) {
                ForEach(importService.pendingWorkouts, id: \.uuid) { workout in
                    WorkoutImportRow(
                        workout: workout,
                        isImportingThis: importingWorkoutId == workout.uuid,
                        isImportingAny: importingWorkoutId != nil || isImportingAll,
                        effectiveColorScheme: effectiveColorScheme,
                        onImport: { importWorkout(workout) }
                    )

                    Rectangle()
                        .fill(effectiveColorScheme == .dark ? .white.opacity(0.08) : .gray.opacity(0.15))
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                }
            }
        }
    }

    // MARK: - Actions

    private func importWorkout(_ hkWorkout: HKWorkout) {
        Task {
            importingWorkoutId = hkWorkout.uuid
            _ = await importService.importWorkout(hkWorkout)
            importingWorkoutId = nil
        }
    }

    private func importAllWorkouts() {
        Task {
            isImportingAll = true

            // Import workouts one by one so we can update UI as each completes
            // Bulk import skips review - imports all valid workouts directly
            let workoutsToImport = importService.pendingWorkouts.filter { workout in
                !importService.isWorkoutImported(workout.uuid.uuidString)
            }

            for workout in workoutsToImport {
                importingWorkoutId = workout.uuid
                _ = await importService.importWorkout(workout)
                importingWorkoutId = nil
            }

            isImportingAll = false

            if unimportedCount == 0 {
                // All imported, dismiss after a brief delay
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                dismiss()
            }
        }
    }
}

// MARK: - Workout Import Row

struct WorkoutImportRow: View {
    let workout: HKWorkout
    let isImportingThis: Bool  // This specific workout is being imported
    let isImportingAny: Bool   // Any import is in progress (disable button)
    let effectiveColorScheme: ColorScheme
    let onImport: () -> Void

    @State private var importService = WorkoutImportService.shared

    private var isImported: Bool {
        importService.isWorkoutImported(workout.uuid.uuidString)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Left side - Date, time, source
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.startDate.formatted(.dateTime.month().day().year()))
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                HStack(spacing: 6) {
                    Text(workout.startDate.formatted(.dateTime.hour().minute()))
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.secondary)

                    Text(formatDuration(workout.duration))
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.secondary)
                }

                Text(workout.sourceRevision.source.name)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Right side - Spinner, Import button, or Imported status
            if isImported {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Imported")
                        .font(.montserratMedium(size: 13))
                }
                .foregroundStyle(.accent)
            } else if isImportingThis {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button {
                    onImport()
                } label: {
                    Text("Import")
                        .font(.montserratSemiBold(size: 14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(.accent)
                        )
                }
                .disabled(isImportingAny)
                .opacity(isImportingAny ? 0.6 : 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

#Preview {
    WorkoutImportSheet()
}
