//
//  WorkoutImportSheet.swift
//  AscendApp
//
//  Created by Claude on 9/1/25.
//

import SwiftUI
import SwiftData

struct WorkoutImportSheet: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var settingsManager = SettingsManager.shared
    @State private var themeManager = ThemeManager.shared
    @State private var importCoordinator = WorkoutImportCoordinator.shared
    @State private var hevyManager = HevyManager.shared
    @State private var showingCelebration = false
    @State private var celebrationData: ImportCelebrationData?
    @State private var importTask: Task<Void, Never>?
    @State private var isSelectionMode = false
    @State private var selectedCandidateIDs: Set<String> = []
    @State private var isRequestingAppleHealthAuthorization = false
    @State private var isEnablingAutoImportFromPrompt = false
    @State private var dismissedAutoImportPromptThisSession = false
    @State private var autoImportStatusMessage: String?
    @State private var setupAlertMessage = ""
    @State private var showingSetupAlert = false

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var candidates: [ImportedWorkoutCandidate] {
        importCoordinator.pendingCandidates
    }

    private var candidateIDs: Set<String> {
        Set(candidates.map(\.id))
    }

    private var candidateCount: Int {
        candidates.count
    }

    private var selectedCount: Int {
        selectedCandidateIDs.intersection(candidateIDs).count
    }

    private var appleHealthConnectionState: AppleHealthConnectionState {
        importCoordinator.appleHealthConnectionState
    }

    private var shouldShowAppleHealthSetupCard: Bool {
        importCoordinator.isAppleHealthAvailable &&
        (appleHealthConnectionState == .neverConnected || appleHealthConnectionState == .revoked)
    }

    private var shouldHideGenericEmptyState: Bool {
        shouldShowAppleHealthSetupCard
    }

    private var shouldShowAutoImportPromptBanner: Bool {
        guard let userID = authVM.user?.uid else { return false }

        return appleHealthConnectionState == .connected &&
            !settingsManager.appleHealthAutoImportEnabled &&
            !dismissedAutoImportPromptThisSession &&
            !settingsManager.hasDismissedAppleHealthAutoImportPrompt(for: userID)
    }

    private var allCandidatesSelected: Bool {
        candidateCount > 0 && selectedCount == candidateCount
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if shouldShowAppleHealthSetupCard {
                        appleHealthSetupCard
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                    }

                    if let autoImportStatusMessage {
                        autoImportEnabledCard(message: autoImportStatusMessage)
                            .padding(.horizontal, 20)
                            .padding(.top, shouldShowAppleHealthSetupCard ? 0 : 20)
                    }

                    if shouldShowAutoImportPromptBanner {
                        AppleHealthAutoImportPromptBanner(
                            effectiveColorScheme: effectiveColorScheme,
                            isEnabling: isEnablingAutoImportFromPrompt,
                            onTurnOn: enableAutoImportFromPrompt,
                            onDismiss: dismissAutoImportPrompt
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, shouldShowAppleHealthSetupCard || autoImportStatusMessage != nil ? 0 : 20)
                    }

                    if shouldHideGenericEmptyState {
                        EmptyView()
                    } else if importCoordinator.isChecking && candidates.isEmpty {
                        loadingStateView
                    } else if candidates.isEmpty {
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
                    .disabled(importCoordinator.isImporting)
                }
            }
        }
        .themedBackground()
        .analyticsScreen(
            WorkoutImportAnalyticsScreen.sheet(
                candidateCount: candidateCount,
                hevyConnected: hevyManager.isConnected
            )
        )
        .interactiveDismissDisabled(importCoordinator.isImporting || showingCelebration)
        .safeAreaInset(edge: .bottom) {
            if isSelectionMode && candidateCount > 0 {
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
        .alert("Apple Health", isPresented: $showingSetupAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(setupAlertMessage)
        }
        .task {
            importCoordinator.configure(modelContext: modelContext)
            syncSelectionWithCandidates()
            await importCoordinator.refreshPendingImports(trigger: .manualReview)
        }
        .onChange(of: candidates.map(\.id)) { _, _ in
            syncSelectionWithCandidates()
        }
    }

    private var actionsMenu: some View {
        Menu {
            Button("Import All", systemImage: "square.and.arrow.down") {
                importAllWorkouts()
            }
            .disabled(candidateCount == 0 || importCoordinator.isImporting)

            Button("Select", systemImage: "checklist") {
                enterSelectionMode()
            }
            .disabled(candidateCount <= 1 || importCoordinator.isImporting)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.accent)
        }
    }

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

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.accent)

            Text("No New Workouts")
                .font(.montserratBold(size: 20))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

            Text(emptyStateMessage)
                .font(.montserratRegular(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .padding(.top, 60)
        .padding(.bottom, 24)
    }

    private var emptyStateMessage: String {
        if shouldShowAppleHealthSetupCard {
            if hevyManager.isConnected {
                return "Connect Apple Health here, or keep importing from your connected sources."
            }
            return "Connect Apple Health above to import existing workouts and optionally auto-import new ones."
        }

        if hevyManager.isConnected {
            return "All your Apple Health and Hevy workouts are already imported."
        }
        return "All your Apple Health workouts are already imported."
    }

    private var appleHealthSetupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image("appleHealth-icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(appleHealthSetupTitle)
                        .font(.montserratSemiBold(size: 16))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                    if !appleHealthSetupSubtitle.isEmpty {
                        Text(appleHealthSetupSubtitle)
                            .font(.montserratRegular(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }

            Text(appleHealthSetupMessage)
                .font(.montserratRegular(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !appleHealthSetupSecondaryLine.isEmpty {
                Text(appleHealthSetupSecondaryLine)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(.secondary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(appleHealthSetupButtonTitle) {
                handleAppleHealthSetupButtonTapped()
            }
            .appSheetButtonStyle()
            .disabled(isRequestingAppleHealthAuthorization)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(effectiveColorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08), lineWidth: 1)
        }
    }

    private var appleHealthSetupTitle: String {
        switch appleHealthConnectionState {
        case .neverConnected:
            return "Import Apple Health workouts"
        case .revoked:
            return "Reconnect Apple Health"
        case .connected, .unavailable:
            return "Apple Health"
        }
    }

    private var appleHealthSetupSubtitle: String {
        switch appleHealthConnectionState {
        case .neverConnected:
            return ""
        case .revoked:
            return "Health permissions were turned off outside Ascend."
        case .connected, .unavailable:
            return ""
        }
    }

    private var appleHealthSetupMessage: String {
        switch appleHealthConnectionState {
        case .neverConnected:
            return "Connect Apple Health to import your existing stairstepper workouts and automatically import new ones when you finish them."
        case .revoked:
            return "Re-enable workout access in the Health app to bring Apple Health workouts into Ascend again."
        case .connected, .unavailable:
            return ""
        }
    }

    private var appleHealthSetupSecondaryLine: String {
        switch appleHealthConnectionState {
        case .neverConnected:
            return "Turn off auto-import anytime in Settings > Edit Profile > Integrations > Apple Health."
        case .revoked, .connected, .unavailable:
            return ""
        }
    }

    private var appleHealthSetupButtonTitle: String {
        if isRequestingAppleHealthAuthorization, appleHealthConnectionState == .neverConnected {
            return "Connecting..."
        }

        switch appleHealthConnectionState {
        case .neverConnected:
            return "Connect Apple Health"
        case .revoked:
            return "Open Health Permissions"
        case .connected, .unavailable:
            return "Manage"
        }
    }

    private var workoutListSection: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    Text("\(candidateCount) NEW WORKOUTS")
                        .font(.montserratSemiBold(size: 12))
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.horizontal, 20)

                if importCoordinator.isImporting && importCoordinator.currentImportingCandidateID != nil {
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
                    Text("\(selectedCount) Selected")
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

            LazyVStack(spacing: 0) {
                ForEach(candidates, id: \.id) { candidate in
                    ImportedWorkoutCandidateRow(
                        candidate: candidate,
                        showSelectionControl: isSelectionMode,
                        isSelected: selectedCandidateIDs.contains(candidate.id),
                        isImportingThis: importCoordinator.currentImportingCandidateID == candidate.id,
                        isImportingAny: importCoordinator.isImporting,
                        effectiveColorScheme: effectiveColorScheme,
                        onToggleSelection: { toggleSelection(for: candidate) },
                        onImport: { importWorkout(candidate) }
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
        SelectionActionBar(
            effectiveColorScheme: effectiveColorScheme,
            secondaryTitle: allCandidatesSelected ? "Deselect All" : "Select All",
            onSecondaryTapped: toggleSelectAll,
            isSecondaryDisabled: importCoordinator.isImporting || candidateCount == 0,
            primaryTitle: "Import Selected (\(selectedCount))",
            onPrimaryTapped: importSelectedWorkouts,
            isPrimaryDisabled: selectedCount == 0 || importCoordinator.isImporting
        )
    }

    private func autoImportEnabledCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.accent)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple Health connected")
                        .font(.montserratSemiBold(size: 16))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                    Text("Auto-import is on")
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button {
                    autoImportStatusMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }

            Text(message)
                .font(.montserratRegular(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(effectiveColorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08), lineWidth: 1)
        }
    }

    private func importWorkout(_ candidate: ImportedWorkoutCandidate) {
        selectedCandidateIDs.remove(candidate.id)
        importTask = Task {
            let outcome = await importCoordinator.importCandidate(candidate)

            switch outcome {
            case .imported(let workout):
                celebrationData = buildCelebrationData(
                    importedWorkouts: [workout],
                    failedCount: 0
                )
                showingCelebration = true
            case .updatedExisting, .failed:
                break
            }

            syncSelectionWithCandidates()
        }
    }

    private func importAllWorkouts() {
        importTask = Task {
            let result = await importCoordinator.importAllCandidates()

            if result.successCount > 0 {
                celebrationData = buildCelebrationData(
                    importedWorkouts: result.importedWorkouts,
                    failedCount: result.failedCount
                )
                showingCelebration = true
            }

            syncSelectionWithCandidates()
        }
    }

    private func importSelectedWorkouts() {
        let selectedIDs = selectedCandidateIDs.intersection(candidateIDs)
        guard !selectedIDs.isEmpty else { return }

        importTask = Task {
            let result = await importCoordinator.importCandidates(ids: selectedIDs)

            if result.successCount > 0 {
                celebrationData = buildCelebrationData(
                    importedWorkouts: result.importedWorkouts,
                    failedCount: result.failedCount
                )
                showingCelebration = true
            }

            syncSelectionWithCandidates()
            exitSelectionMode(clearSelection: true)
        }
    }

    private func toggleSelection(for candidate: ImportedWorkoutCandidate) {
        if selectedCandidateIDs.contains(candidate.id) {
            selectedCandidateIDs.remove(candidate.id)
        } else {
            selectedCandidateIDs.insert(candidate.id)
        }
    }

    private func toggleSelectAll() {
        if allCandidatesSelected {
            selectedCandidateIDs.subtract(candidateIDs)
        } else {
            selectedCandidateIDs.formUnion(candidateIDs)
        }
    }

    private func syncSelectionWithCandidates() {
        selectedCandidateIDs.formIntersection(candidateIDs)
        if candidateCount <= 1 {
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
            selectedCandidateIDs.removeAll()
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            isSelectionMode = false
        }
    }

    private func handleAppleHealthSetupButtonTapped() {
        switch appleHealthConnectionState {
        case .neverConnected:
            requestAppleHealthAuthorization()
        case .revoked:
            openHealthPermissions()
        case .connected, .unavailable:
            break
        }
    }

    private func requestAppleHealthAuthorization() {
        guard !isRequestingAppleHealthAuthorization else { return }

        isRequestingAppleHealthAuthorization = true
        Task {
            let didConnect = await importCoordinator.requestAppleHealthAuthorizationIfNeeded()

            guard didConnect else {
                await MainActor.run {
                    isRequestingAppleHealthAuthorization = false
                    if let errorMessage = importCoordinator.lastErrorMessage, !errorMessage.isEmpty {
                        presentSetupAlert(errorMessage)
                    }
                }
                return
            }

            await MainActor.run {
                isRequestingAppleHealthAuthorization = false
                settingsManager.setAppleHealthAutoImportEnabled(true)
                autoImportStatusMessage = defaultAutoImportStatusMessage
            }
            await importCoordinator.handleAppleHealthAutoImportPreferenceChanged()
        }
    }

    private func openHealthPermissions() {
        guard let healthURL = URL(string: "x-apple-health://") else { return }
        openURL(healthURL)
    }

    private func enableAutoImportFromPrompt() {
        guard !isEnablingAutoImportFromPrompt else { return }

        dismissAutoImportPrompt()
        isEnablingAutoImportFromPrompt = true
        settingsManager.setAppleHealthAutoImportEnabled(true)

        Task {
            await importCoordinator.handleAppleHealthAutoImportPreferenceChanged()
            await MainActor.run {
                isEnablingAutoImportFromPrompt = false
                autoImportStatusMessage = defaultAutoImportStatusMessage
            }
        }
    }

    private func dismissAutoImportPrompt() {
        dismissedAutoImportPromptThisSession = true

        if let userID = authVM.user?.uid {
            settingsManager.markAppleHealthAutoImportPromptDismissed(for: userID)
        }
    }

    private var defaultAutoImportStatusMessage: String {
        "New Apple Health workouts will auto-import by default. You can change this anytime in Settings > Edit Profile > Integrations > Apple Health."
    }

    private func presentSetupAlert(_ message: String) {
        setupAlertMessage = message
        showingSetupAlert = true
    }

    private func buildCelebrationData(
        importedWorkouts: [Workout],
        failedCount: Int
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
            verticalClimbUnit: settings.measurementSystem.distanceUnit
        )
    }
}

struct ImportedWorkoutCandidateRow: View {
    let candidate: ImportedWorkoutCandidate
    let showSelectionControl: Bool
    let isSelected: Bool
    let isImportingThis: Bool
    let isImportingAny: Bool
    let effectiveColorScheme: ColorScheme
    let onToggleSelection: () -> Void
    let onImport: () -> Void

    var body: some View {
        Group {
            if showSelectionControl {
                Button(action: onToggleSelection) {
                    rowContent
                }
                .buttonStyle(.plain)
                .disabled(isImportingAny)
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

            sourceIcon
                .frame(width: 28, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.displayName)
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                HStack(spacing: 6) {
                    Text(candidate.startDate.formatted(.dateTime.month().day().year()))
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.secondary)

                    Text("\u{2022}")
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.secondary)

                    Text(candidate.startDate.formatted(.dateTime.hour().minute()))
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.secondary)

                    Text("\u{2022}")
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.secondary)

                    Text(formatDuration(candidate.duration))
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.secondary)
                }

                Text(candidate.sourceDisplayName)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isImportingThis {
                ProgressView()
                    .scaleEffect(0.8)
            } else if !showSelectionControl {
                Button(action: onImport) {
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
        switch candidate.kind {
        case .linkedHevyAppleHealth:
            HStack(spacing: -6) {
                Image("hevy-icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .clipShape(.rect(cornerRadius: 4))

                Image(systemName: "heart.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(4)
                    .background(.white)
                    .clipShape(.circle)
            }
        case .hevy:
            Image("hevy-icon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .clipShape(.rect(cornerRadius: 4))
        case .appleHealth:
            Image(systemName: "heart.fill")
                .font(.system(size: 14))
                .foregroundStyle(.red)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(minutes < 10 ? "0" : "")\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
        }

        return "\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
    }
}

#Preview {
    WorkoutImportSheet()
        .environment(AuthenticationViewModel())
        .modelContainer(for: [Workout.self, WorkoutSourceLink.self], inMemory: true)
}
