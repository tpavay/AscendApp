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
    @State private var unifiedImportService = UnifiedImportService.shared
    @State private var hevyManager = HevyManager.shared
    @State private var showingCelebration = false
    @State private var celebrationData: ImportCelebrationData?
    @State private var importTask: Task<Void, Never>?

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var unimportedCount: Int {
        unifiedImportService.pendingWorkouts.filter { workout in
            !unifiedImportService.isWorkoutImported(workout)
        }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Content
                    if unifiedImportService.isLoading {
                        loadingStateView
                    } else if unifiedImportService.pendingWorkouts.isEmpty {
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
                        importTask?.cancel()
                        dismiss()
                    }
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(.accent)
                    .disabled(unifiedImportService.isImporting)
                }
            }
        }
        .themedBackground()
        .interactiveDismissDisabled(unifiedImportService.isImporting || showingCelebration)
        .fullScreenCover(isPresented: $showingCelebration) {
            if let data = celebrationData {
                ImportCelebrationView(data: data) {
                    showingCelebration = false
                    dismiss()
                }
            }
        }
    }

    // MARK: - Loading State

    private var loadingStateView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Checking for workouts...")
                .font(.montserratMedium(size: 16))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 60)
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

            Text(hevyManager.isConnected
                 ? "All your Apple Health and Hevy workouts have already been imported."
                 : "All your Apple Health workouts have already been imported.")
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

                    if unifiedImportService.isImporting && unifiedImportService.currentImportingPendingId != nil {
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
                        .disabled(unifiedImportService.isImporting)
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
                ForEach(unifiedImportService.pendingWorkouts, id: \.id) { pending in
                    PendingWorkoutImportRow(
                        pending: pending,
                        isImportingThis: unifiedImportService.currentImportingPendingId == pending.id,
                        isImportingAny: unifiedImportService.isImporting,
                        autoLinkEnabled: hevyManager.autoLinkAppleHealth,
                        effectiveColorScheme: effectiveColorScheme,
                        onImport: { importWorkout(pending) }
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

    private func importWorkout(_ pending: PendingWorkout) {
        importTask = Task {
            let outcome = await unifiedImportService.importWorkout(pending)

            if case .imported(let workout) = outcome,
               FeatureFlags.isImportCelebrationEnabled {
                let data = buildCelebrationData(importedWorkouts: [workout], failedCount: 0)
                celebrationData = data
                showingCelebration = true
            }
        }
    }

    private func importAllWorkouts() {
        importTask = Task {
            let result = await unifiedImportService.importAllWorkouts()

            if FeatureFlags.isImportCelebrationEnabled && result.successCount > 0 {
                let data = buildCelebrationData(
                    importedWorkouts: result.importedWorkouts,
                    failedCount: result.failedCount
                )
                celebrationData = data
                showingCelebration = true
            } else if result.successCount > 0 {
                // Old behavior: auto-dismiss
                try? await Task.sleep(for: .seconds(1))
                dismiss()
            }
        }
    }

    private func buildCelebrationData(importedWorkouts: [Workout], failedCount: Int) -> ImportCelebrationData {
        let settings = SettingsManager.shared
        let totalDuration = importedWorkouts.reduce(0.0) { $0 + $1.duration }
        let totalSteps = importedWorkouts.reduce(0) { $0 + $1.steps }
        let totalFloors = importedWorkouts.reduce(0) { $0 + $1.floors }
        let totalVerticalClimb = importedWorkouts.reduce(0.0) {
            $0 + $1.totalVerticalClimb(
                stepHeight: settings.stepHeight,
                measurementSystem: settings.measurementSystem
            )
        }

        return ImportCelebrationData(
            importedCount: importedWorkouts.count,
            failedCount: failedCount,
            totalDuration: totalDuration,
            totalSteps: totalSteps,
            totalFloors: totalFloors,
            totalVerticalClimb: totalVerticalClimb,
            verticalClimbUnit: settings.measurementSystem.distanceUnit
        )
    }
}

// MARK: - Pending Workout Import Row

struct PendingWorkoutImportRow: View {
    let pending: PendingWorkout
    let isImportingThis: Bool  // This specific workout is being imported
    let isImportingAny: Bool   // Any import is in progress (disable button)
    let autoLinkEnabled: Bool
    let effectiveColorScheme: ColorScheme
    let onImport: () -> Void

    @State private var unifiedImportService = UnifiedImportService.shared

    private var isImported: Bool {
        unifiedImportService.isWorkoutImported(pending)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Source icon
            sourceIcon
                .frame(width: 24, height: 24)

            // Left side - Date, time, source
            VStack(alignment: .leading, spacing: 4) {
                Text(pending.startDate.formatted(.dateTime.month().day().year()))
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                HStack(spacing: 6) {
                    Text(pending.startDate.formatted(.dateTime.hour().minute()))
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.secondary)

                    Text("\u{2022}")
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.secondary)

                    Text(formatDuration(pending.duration))
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.secondary)
                }

                Text(pending.displaySourceName(autoLinkEnabled: autoLinkEnabled))
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

    @ViewBuilder
    private var sourceIcon: some View {
        switch pending.source {
        case .appleHealth:
            Image(systemName: "heart.fill")
                .font(.system(size: 14))
                .foregroundStyle(.red)
        case .hevy:
            Image("hevy-icon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .clipShape(.rect(cornerRadius: 4))
        case .manual:
            Image(systemName: "hand.draw.fill")
                .font(.system(size: 14))
                .foregroundStyle(.blue)
        case .garmin, .strava, .fitbit:
            // Future integrations - show generic icon
            Image(systemName: "figure.walk")
                .font(.system(size: 14))
                .foregroundStyle(.blue)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(minutes < 10 ? "0" : "")\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
        } else {
            return "\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
        }
    }
}

#Preview {
    WorkoutImportSheet()
}
