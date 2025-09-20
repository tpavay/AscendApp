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
    @State private var isImporting = false
    @State private var importedCount = 0
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if importService.pendingWorkouts.isEmpty {
                    // No workouts to import
                    ContentUnavailableView(
                        "No New Workouts",
                        systemImage: "checkmark.circle",
                        description: Text("All your Apple Health workouts have already been imported.")
                    )
                } else {
                    // Header with import all button
                    VStack(spacing: 16) {
                        HStack {
                            Text("\(importService.pendingWorkoutsCount) New Workouts")
                                .font(.montserratBold(size: 20))
                                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                            
                            Spacer()
                            
                            let unimportedCount = importService.pendingWorkouts.filter { workout in
                                !importService.isWorkoutImported(workout.uuid.uuidString)
                            }.count
                            
                            Button(unimportedCount > 0 ? "Import All (\(unimportedCount))" : "All Imported") {
                                if unimportedCount > 0 {
                                    importAllWorkouts()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isImporting || unimportedCount == 0)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        
                        if isImporting {
                            ProgressView("Importing workouts...")
                                .font(.montserratRegular(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        
                        Divider()
                            .background(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))
                    }
                    
                    // Workout list
                    List {
                        ForEach(importService.pendingWorkouts, id: \.uuid) { workout in
                            WorkoutImportRow(
                                workout: workout,
                                isImporting: isImporting,
                                onImport: { importWorkout(workout) }
                            )
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("Import Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.montserratMedium(size: 16))
                }
            }
        }
        .themedBackground()
    }
    
    private func importWorkout(_ hkWorkout: HKWorkout) {
        Task {
            isImporting = true
            let success = await importService.importWorkout(hkWorkout)
            isImporting = false
            
            if success {
                importedCount += 1
            }
        }
    }
    
    private func importAllWorkouts() {
        Task {
            isImporting = true
            let count = await importService.importAllWorkouts()
            isImporting = false
            importedCount = count
            
            if importService.pendingWorkoutsCount == 0 {
                // All imported, dismiss after a brief delay
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                dismiss()
            }
        }
    }
}

struct WorkoutImportRow: View {
    let workout: HKWorkout
    let isImporting: Bool
    let onImport: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var importService = WorkoutImportService.shared
    
    private var isImported: Bool {
        importService.isWorkoutImported(workout.uuid.uuidString)
    }
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Workout icon
            Image(systemName: "figure.stair.stepper")
                .font(.system(size: 24))
                .foregroundStyle(.blue)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(.blue.opacity(0.1))
                )
            
            // Workout info  
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(workout.startDate.formatted(date: .numeric, time: .shortened))
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    Text("•")
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(.secondary)
                    
                    Text(formatDuration(workout.duration))
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("From \(workout.sourceRevision.source.name)")
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(.blue)
                    .lineLimit(1)

            }
            
            Spacer()
            
            // Import button
            if isImported {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.green)
                    Text("Imported")
                        .font(.montserratMedium(size: 13))
                        .foregroundStyle(.green)
                }
            } else {
                Button("Import") {
                    onImport()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isImporting)
            }
        }
        .padding(.vertical, 8)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
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
