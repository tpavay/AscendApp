//
//  WorkoutImportSheet.swift
//  AscendApp
//
//  Created by Claude on 9/1/25.
//

import SwiftUI
import HealthKit
import SwiftData

struct WorkoutImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var unifiedImportService = UnifiedImportService.shared
    @State private var hevyManager = HevyManager.shared
    @State private var showingCelebration = false
    @State private var celebrationData: ImportCelebrationData?
    @State private var importTask: Task<Void, Never>?
    @State private var isSelectionMode = false
    @State private var selectedPendingIds: Set<String> = []

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var unimportedPendingWorkouts: [PendingWorkout] {
        unifiedImportService.pendingWorkouts.filter { workout in
            !unifiedImportService.isWorkoutImported(workout)
        }
    }

    private var unimportedCount: Int {
        unimportedPendingWorkouts.count
    }

    private var unimportedPendingIds: Set<String> {
        Set(unimportedPendingWorkouts.map(\.id))
    }

    private var selectedUnimportedCount: Int {
        selectedPendingIds.intersection(unimportedPendingIds).count
    }

    private var allUnimportedSelected: Bool {
        unimportedCount > 0 && selectedUnimportedCount == unimportedCount
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
            .navigationTitle(isSelectionMode ? "Select Workouts" : "Import Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !isSelectionMode {
                        actionsMenu
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isSelectionMode ? "Cancel" : "Done") {
                        if isSelectionMode {
                            exitSelectionMode()
                        } else {
                            importTask?.cancel()
                            dismiss()
                        }
                    }
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(.accent)
                    .disabled(unifiedImportService.isImporting)
                }
            }
        }
        .themedBackground()
        .interactiveDismissDisabled(unifiedImportService.isImporting || showingCelebration)
        .safeAreaInset(edge: .bottom) {
            if isSelectionMode && unimportedCount > 0 {
                batchActionBar
            }
        }
        .fullScreenCover(isPresented: $showingCelebration) {
            if let data = celebrationData {
                ImportCelebrationView(data: data) {
                    showingCelebration = false
                    dismiss()
                }
            }
        }
        .onAppear {
            syncSelectionWithPendingWorkouts()
        }
        .onChange(of: unifiedImportService.pendingWorkouts.map(\.id)) { _, _ in
            syncSelectionWithPendingWorkouts()
        }
    }

    private var actionsMenu: some View {
        Menu {
            Button("Import All", systemImage: "square.and.arrow.down") {
                importAllWorkouts()
            }
            .disabled(unimportedCount == 0 || unifiedImportService.isImporting)

            Button("Select", systemImage: "checklist") {
                enterSelectionMode()
            }
            .disabled(unimportedCount <= 1 || unifiedImportService.isImporting)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.accent)
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
            VStack(spacing: 10) {
                HStack {
                    Text("\(unimportedCount) NEW WORKOUTS")
                        .font(.montserratSemiBold(size: 12))
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.horizontal, 20)

                if unifiedImportService.isImporting && unifiedImportService.currentImportingPendingId != nil {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Importing workouts...")
                            .font(.montserratRegular(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                } else if isSelectionMode {
                    Text("\(selectedUnimportedCount) Selected")
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                }

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
                        showSelectionControl: isSelectionMode,
                        isSelected: selectedPendingIds.contains(pending.id),
                        isImportingThis: unifiedImportService.currentImportingPendingId == pending.id,
                        isImportingAny: unifiedImportService.isImporting,
                        autoLinkEnabled: hevyManager.autoLinkAppleHealth,
                        effectiveColorScheme: effectiveColorScheme,
                        onToggleSelection: { toggleSelection(for: pending) },
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

    private var batchActionBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))
                .frame(height: 1)

            HStack(spacing: 10) {
                Button {
                    toggleSelectAll()
                } label: {
                    Text(allUnimportedSelected ? "Deselect All" : "Select All")
                        .font(.montserratSemiBold(size: 15))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(effectiveColorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.06))
                        )
                }
                .disabled(unifiedImportService.isImporting || unimportedCount == 0)

                Button {
                    importSelectedWorkouts()
                } label: {
                    Text("Import Selected (\(selectedUnimportedCount))")
                        .font(.montserratSemiBold(size: 15))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(.accent)
                        )
                }
                .disabled(selectedUnimportedCount == 0 || unifiedImportService.isImporting)
                .opacity(selectedUnimportedCount == 0 || unifiedImportService.isImporting ? 0.45 : 1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(effectiveColorScheme == .dark ? .black.opacity(0.95) : .white.opacity(0.97))
    }

    // MARK: - Actions

    private func importWorkout(_ pending: PendingWorkout) {
        selectedPendingIds.remove(pending.id)
        importTask = Task {
            let referenceDate = Date()
            let preGoalCapture = capturePreGoalSnapshot(referenceDate: referenceDate)
            let outcome = await unifiedImportService.importWorkout(pending)

            if case .imported(let workout) = outcome {
                let goalSnapshot = buildGoalSnapshot(preGoalCapture: preGoalCapture)
                let data = buildCelebrationData(
                    importedWorkouts: [workout],
                    failedCount: 0,
                    goalSnapshot: goalSnapshot
                )
                celebrationData = data
                showingCelebration = true
            }

            syncSelectionWithPendingWorkouts()
        }
    }

    private func importAllWorkouts() {
        importTask = Task {
            let referenceDate = Date()
            let preGoalCapture = capturePreGoalSnapshot(referenceDate: referenceDate)
            let result = await unifiedImportService.importAllWorkouts()

            if result.successCount > 0 {
                let goalSnapshot = buildGoalSnapshot(preGoalCapture: preGoalCapture)
                let data = buildCelebrationData(
                    importedWorkouts: result.importedWorkouts,
                    failedCount: result.failedCount,
                    goalSnapshot: goalSnapshot
                )
                celebrationData = data
                showingCelebration = true
            }

            syncSelectionWithPendingWorkouts()
        }
    }

    private func importSelectedWorkouts() {
        let selectedIds = selectedPendingIds.intersection(unimportedPendingIds)
        guard !selectedIds.isEmpty else { return }

        importTask = Task {
            let referenceDate = Date()
            let preGoalCapture = capturePreGoalSnapshot(referenceDate: referenceDate)
            let result = await unifiedImportService.importSelectedWorkouts(pendingIds: selectedIds)

            if result.successCount > 0 {
                let goalSnapshot = buildGoalSnapshot(preGoalCapture: preGoalCapture)
                let data = buildCelebrationData(
                    importedWorkouts: result.importedWorkouts,
                    failedCount: result.failedCount,
                    goalSnapshot: goalSnapshot
                )
                celebrationData = data
                showingCelebration = true
            }

            syncSelectionWithPendingWorkouts()
            exitSelectionMode(clearSelection: true)
        }
    }

    private func toggleSelection(for pending: PendingWorkout) {
        guard !unifiedImportService.isWorkoutImported(pending) else { return }

        if selectedPendingIds.contains(pending.id) {
            selectedPendingIds.remove(pending.id)
        } else {
            selectedPendingIds.insert(pending.id)
        }
    }

    private func toggleSelectAll() {
        if allUnimportedSelected {
            selectedPendingIds.subtract(unimportedPendingIds)
        } else {
            selectedPendingIds.formUnion(unimportedPendingIds)
        }
    }

    private func syncSelectionWithPendingWorkouts() {
        selectedPendingIds.formIntersection(unimportedPendingIds)
        if unimportedCount <= 1 {
            isSelectionMode = false
        }
    }

    private func enterSelectionMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSelectionMode = true
        }
    }

    private func exitSelectionMode(clearSelection: Bool = true) {
        if clearSelection {
            selectedPendingIds.removeAll()
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            isSelectionMode = false
        }
    }

    private typealias PreGoalCapture = (goal: Goal, progress: GoalProgress, referenceDate: Date)

    private func capturePreGoalSnapshot(referenceDate: Date) -> PreGoalCapture? {
        do {
            let existingWorkouts = try ImportCelebrationService.fetchAllWorkouts(modelContext: modelContext)
            guard let capture = ImportCelebrationService.captureGoalSnapshot(
                modelContext: modelContext,
                existingWorkouts: existingWorkouts,
                referenceDate: referenceDate
            ) else {
                return nil
            }
            return (goal: capture.goal, progress: capture.progress, referenceDate: referenceDate)
        } catch {
            return nil
        }
    }

    private func buildGoalSnapshot(preGoalCapture: PreGoalCapture?) -> GoalCelebrationSnapshot? {
        guard let preGoalCapture else { return nil }

        do {
            let allWorkoutsAfterImport = try ImportCelebrationService.fetchAllWorkouts(modelContext: modelContext)
            return ImportCelebrationService.buildGoalData(
                preGoal: preGoalCapture.goal,
                preProgress: preGoalCapture.progress,
                allWorkoutsAfterImport: allWorkoutsAfterImport,
                referenceDate: preGoalCapture.referenceDate
            )
        } catch {
            return nil
        }
    }

    private func buildCelebrationData(
        importedWorkouts: [Workout],
        failedCount: Int,
        goalSnapshot: GoalCelebrationSnapshot?
    ) -> ImportCelebrationData {
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
            verticalClimbUnit: settings.measurementSystem.distanceUnit,
            goalSnapshot: goalSnapshot
        )
    }
}

// MARK: - Pending Workout Import Row

struct PendingWorkoutImportRow: View {
    let pending: PendingWorkout
    let showSelectionControl: Bool
    let isSelected: Bool
    let isImportingThis: Bool  // This specific workout is being imported
    let isImportingAny: Bool   // Any import is in progress (disable button)
    let autoLinkEnabled: Bool
    let effectiveColorScheme: ColorScheme
    let onToggleSelection: () -> Void
    let onImport: () -> Void

    @State private var unifiedImportService = UnifiedImportService.shared

    private var isImported: Bool {
        unifiedImportService.isWorkoutImported(pending)
    }

    var body: some View {
        Group {
            if showSelectionControl {
                Button {
                    onToggleSelection()
                } label: {
                    rowContent
                }
                .buttonStyle(.plain)
                .disabled(isImported || isImportingAny)
                .opacity(isImported ? 0.6 : 1)
            } else {
                rowContent
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 12) {
            if showSelectionControl {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isSelected ? .accent : .secondary)
            }

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
            } else if showSelectionControl {
                EmptyView()
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
