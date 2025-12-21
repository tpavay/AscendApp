//
//  WorkoutDetailView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/28/25.
//

import SwiftUI

struct WorkoutDetailView: View {
    let workout: Workout
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationViewModel.self) private var authVM
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared
    @State private var showingEditWorkout = false
    @State private var showingShareWorkoutView = false
    @State private var showingDeleteConfirmation = false
    @State private var showingDeleteError = false
    @State private var deleteErrorMessage = ""
    @State private var stravaManager = StravaManager.shared
    @State private var isSyncingToStrava = false
    @State private var syncingIconOpacity: Double = 1.0
    @State private var showingStravaSyncSuccess = false
    @State private var stravaSyncError: String? = nil
    @State private var isDeleting = false
    @State private var isCancelling = false
    @State private var deleteTask: Task<Void, Never>? = nil
    @State private var isNotesExpanded = false

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header with workout name and date
                    headerSection

                    // Notes (if available) - shown after PRs, before stats
                    if !workout.notes.isEmpty {
                        notesSection
                    }

                    // Workout Details
                    workoutDetailsSection

                    // Photos (if available)
                    if !workout.photos.isEmpty {
                        WorkoutPhotosSection(workout: workout)
                    }

                    // Heart Rate Chart (if heart rate data is available)
                    if !workout.heartRateTimeSeries.isEmpty {
                        HeartRateChartView(
                            heartRateData: workout.heartRateTimeSeries,
                            workoutStartTime: workout.date,
                            workoutDuration: workout.duration
                        )
                    }

                    // Additional metrics (e.g., calories, METs, vertical climb)
                    if hasAdditionalMetrics {
                        additionalMetricsSection
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
            .themedBackground()
            .navigationBarHidden(true)
            .overlay(
                // Custom header bar
                VStack {
                    customHeader
                    Spacer()
                }
            )
            .sheet(isPresented: $showingEditWorkout) {
                EditWorkoutView(
                    workout: workout,
                    showingEditWorkout: $showingEditWorkout
                )
                .interactiveDismissDisabled()
            }
            .sheet(isPresented: $showingShareWorkoutView) {
                WorkoutShareCarouselView(workout: workout, displayName: authVM.displayName)
            }
            .onAppear {
                // Preload share card templates in background (anticipate sharing)
                ShareCardTemplateService.shared.preloadIfNeeded()
            }
            .sheet(isPresented: $showingDeleteConfirmation) {
                SingleWorkoutDeleteConfirmationView(
                    workout: workout,
                    isLoading: isDeleting,
                    isCancelling: isCancelling,
                    onConfirm: {
                        // Guard against double-starting
                        guard deleteTask == nil else { return }
                        deleteTask = Task {
                            await deleteWorkout()
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
                .presentationDetents([.height(200)])
                .interactiveDismissDisabled(isDeleting || isCancelling)
                .onDisappear {
                    deleteTask?.cancel()
                    deleteTask = nil
                }
            }
        }
    }
    
    private var customHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.accent)
                }
                
                Spacer()
                
                Text("Workout Details")
                    .font(.montserratSemiBold(size: 18))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Spacer()
                
                Menu {
                    Button(action: {
                        showingShareWorkoutView = true
                    }) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }

                    // Strava sync option
                    if stravaManager.isConnected {
                        if workout.isSyncedToStrava {
                            // Show synced state (non-actionable)
                            Label("Synced to Strava", systemImage: "checkmark.circle.fill")
                        } else {
                            Button(action: shareToStrava) {
                                if isSyncingToStrava {
                                    Label("Syncing...", systemImage: "arrow.triangle.2.circlepath")
                                } else {
                                    HStack {
                                        Image("strava-icon")
                                            .renderingMode(.template)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 13, height: 13)
                                        Text("Sync to Strava")
                                    }
                                }
                            }
                            .disabled(isSyncingToStrava)
                        }
                    }

                    Button(action: {
                        showingEditWorkout = true
                    }) {
                        Label("Edit Workout", systemImage: "pencil")
                    }

                    Button(role: .destructive, action: {
                        showingDeleteConfirmation = true
                    }) {
                        Label("Delete Workout", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .background(effectiveColorScheme == .dark ? .black : .white)
            
            Divider()
                .background(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))
        }
        .background(effectiveColorScheme == .dark ? .black : .white)
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Workout name
            Text(workout.name)
                .font(.montserratBold(size: 24))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                .multilineTextAlignment(.center)
            
            // Personal Records Badges
            if workout.hasPersonalRecords {
                PersonalRecordBadgeGroup(
                    workout: workout,
                    size: .medium,
                    maxVisible: nil
                )
                .padding(.top, 4)
            }

            // Strava sync indicator
            if isSyncingToStrava || workout.isSyncedToStrava {
                HStack(spacing: 6) {
                    Image("strava-icon")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .opacity(isSyncingToStrava ? syncingIconOpacity : 1.0)
                    Text(isSyncingToStrava ? "Syncing..." : "Synced to Strava")
                        .font(.montserratRegular(size: 12))
                }
                .foregroundStyle(Color(red: 252/255, green: 76/255, blue: 2/255)) // Strava orange
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color(red: 252/255, green: 76/255, blue: 2/255).opacity(0.15))
                )
                .onChange(of: isSyncingToStrava) { _, syncing in
                    if syncing {
                        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                            syncingIconOpacity = 0.3
                        }
                    } else {
                        withAnimation(.default) {
                            syncingIconOpacity = 1.0
                        }
                    }
                }
            }

            // Date & time
            VStack(spacing: 4) {
                Text(formatWorkoutDateTime())
                    .font(.montserratRegular(size: 16))
                    .foregroundStyle(.accent)
            }
        }
        .padding(.top, 80) // Account for custom header
    }
    
    private var workoutDetailsSection: some View {
        VStack(spacing: 16) {
            // Section header
            HStack {
                Text("Workout Summary")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                Spacer()
            }
            
            VStack(spacing: 16) {
                // Square grid for main metrics
                if workout.avgHeartRate != nil || workout.maxHeartRate != nil {
                    // Show duration, steps/floors, avg HR, max HR in square
                    squareMetricsGrid
                    
                    // Show pace below
                    additionalMetrics
                } else {
                    // Show duration, steps/floors, pace in square
                    fullWorkoutMetricsGrid
                }
                
                // Effort rating (if available)
                if let effortRating = workout.effortRating {
                    statCard(
                        icon: "bolt.fill",
                        title: "Effort Rating",
                        value: "\(Int(effortRating))/5",
                        subtitle: effortDescription(for: effortRating),
                        iconColor: .orange
                    )
                }
            }
        }
    }
    
    private var preferredMetric: WorkoutMetric {
        settingsManager.preferredWorkoutMetric
    }
    
    private var squareMetricsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
            // Duration
            gridStatCard(
                icon: "stopwatch",
                title: "Duration",
                value: workout.durationFormatted
            )
            
            // Primary metric based on user preference
            gridStatCard(
                icon: preferredMetric == .steps ? "figure.stairs" : "building.2",
                title: preferredMetric.displayName,
                value: "\(workout.metricValue(for: preferredMetric))"
            )
            
            // Average Heart Rate
            if let avgHR = workout.avgHeartRate {
                gridStatCard(
                    icon: "heart.fill",
                    title: "Avg Heart Rate",
                    value: "\(avgHR)",
                    iconColor: .red
                )
            } else {
                gridStatCard(icon: "minus", title: "No Data", value: "—")
            }
            
            // Max Heart Rate
            if let maxHR = workout.maxHeartRate {
                gridStatCard(
                    icon: "heart.fill",
                    title: "Max Heart Rate",
                    value: "\(maxHR)",
                    iconColor: .red
                )
            } else {
                gridStatCard(icon: "minus", title: "No Data", value: "—")
            }
        }
    }
    
    private var fullWorkoutMetricsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
            // Duration
            gridStatCard(
                icon: "stopwatch",
                title: "Duration",
                value: workout.durationFormatted
            )
            
            // Primary metric based on user preference
            gridStatCard(
                icon: preferredMetric == .steps ? "figure.stairs" : "building.2",
                title: preferredMetric.displayName,
                value: "\(workout.metricValue(for: preferredMetric))"
            )
            
            // Pace based on user preference
            if let pace = workout.pace(for: preferredMetric) {
                gridStatCard(
                    icon: "speedometer",
                    title: "Pace",
                    value: String(format: "%.1f", pace)
                )
            } else {
                gridStatCard(icon: "minus", title: "No Data", value: "—")
            }
        }
    }
    
    private var additionalMetrics: some View {
        VStack(spacing: 16) {
            // Pace based on user preference
            if let pace = workout.pace(for: preferredMetric) {
                statCard(
                    icon: "speedometer",
                    title: "Pace",
                    value: String(format: "%.1f", pace),
                    subtitle: "\(preferredMetric.unit)/min"
                )
            }
        }
    }
    
    private var additionalMetricsSection: some View {
        VStack(spacing: 16) {
            // Section header
            HStack {
                Text("Additional Metrics")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                Spacer()
            }

            if let verticalClimb = verticalClimbValue {
                statCard(
                    icon: "arrow.up",
                    title: "Vertical Climb",
                    value: String(format: "%.1f", verticalClimb),
                    subtitle: workout.verticalClimbUnit(measurementSystem: settingsManager.measurementSystem)
                )
            }
            
            if let calories = workout.caloriesBurned {
                statCard(
                    icon: "flame.fill",
                    title: "Calories Burned",
                    value: "\(calories)",
                    subtitle: "calories",
                    iconColor: .orange
                )
            }
            
            if let averageMETs = workout.averageMETs {
                statCard(
                    icon: "bolt.circle.fill",
                    title: "Average METs",
                    value: String(format: "%.1f", averageMETs),
                    subtitle: "METs",
                    iconColor: .green
                )
            }
        }
    }

    private var hasAdditionalMetrics: Bool {
        verticalClimbValue != nil || workout.caloriesBurned != nil || workout.averageMETs != nil
    }

    private var verticalClimbValue: Double? {
        workout.totalVerticalClimb(
            stepHeight: settingsManager.stepHeight,
            measurementSystem: settingsManager.measurementSystem
        )
    }
    
    /// Check if notes need truncation (more than ~4 lines worth of text)
    private var notesNeedsTruncation: Bool {
        // Approximate check: ~60 chars per line at this font size, so ~240 for 4 lines
        workout.notes.count > 240 || workout.notes.components(separatedBy: "\n").count > 4
    }

    private var notesSection: some View {
        VStack(spacing: 16) {
            // Section header
            HStack {
                Text("Notes")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(workout.notes)
                    .font(.montserratRegular(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(isNotesExpanded ? nil : 4)

                if isNotesExpanded {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isNotesExpanded = false
                        }
                    } label: {
                        Text("Show less")
                            .font(.montserratMedium(size: 14))
                            .foregroundStyle(.accent)
                    }
                }
            }
            .padding(20)
            .contentShape(Rectangle())
            .onTapGesture {
                if notesNeedsTruncation && !isNotesExpanded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isNotesExpanded = true
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                    )
            )
        }
    }
    
    private func statCard(
        icon: String,
        title: String,
        value: String,
        subtitle: String? = nil,
        iconColor: Color = .accent,
        isProminent: Bool = false
    ) -> some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: isProminent ? 24 : 20, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: isProminent ? 32 : 28)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.montserratMedium(size: isProminent ? 16 : 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(.montserratBold(size: isProminent ? 28 : 20))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.montserratRegular(size: isProminent ? 16 : 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    }
                }
            }
            
            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                )
        )
    }
    
    private func gridStatCard(
        icon: String,
        title: String,
        value: String,
        iconColor: Color = .accent
    ) -> some View {
        VStack(spacing: 6) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(height: 20)

            // Content
            VStack(spacing: 2) {
                Text(title)
                    .font(.montserratMedium(size: 11))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(value)
                    .font(.montserratBold(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                )
        )
    }
    
    private func formatWorkoutDateTime() -> String {
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        
        if calendar.isDateInToday(workout.date) {
            return "Today at \(timeFormatter.string(from: workout.date))"
        } else if calendar.isDateInYesterday(workout.date) {
            return "Yesterday at \(timeFormatter.string(from: workout.date))"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"
            // Check if it's from this year
            if calendar.component(.year, from: workout.date) == calendar.component(.year, from: Date()) {
                return "\(dateFormatter.string(from: workout.date)) at \(timeFormatter.string(from: workout.date))"
            } else {
                dateFormatter.dateFormat = "MMM d, yyyy"
                return "\(dateFormatter.string(from: workout.date)) at \(timeFormatter.string(from: workout.date))"
            }
        }
    }
    
    private func effortDescription(for rating: Double) -> String {
        switch Int(rating) {
        case 1:
            return "Minimal"
        case 2:
            return "Light"
        case 3:
            return "Moderate"
        case 4:
            return "High"
        case 5:
            return "Maximum"
        default:
            return "Moderate"
        }
    }
    
    private func shareToStrava() {
        guard !workout.isSyncedToStrava else { return }

        Task {
            isSyncingToStrava = true
            stravaSyncError = nil

            do {
                let activityId = try await stravaManager.syncWorkout(
                    workout,
                    primaryMetric: settingsManager.preferredWorkoutMetric
                )

                // Update workout with sync metadata
                let metadata = StravaSyncMetadata(stravaActivityId: activityId)
                workout.setStravaSyncMetadata(metadata)
                try? modelContext.save()

                HapticsManager.shared.trigger(.success)
                showingStravaSyncSuccess = true

                // Auto-dismiss the success message after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showingStravaSyncSuccess = false
                }
            } catch {
                stravaSyncError = error.localizedDescription
                HapticsManager.shared.trigger(.error)
            }

            isSyncingToStrava = false
        }
    }

    private func deleteWorkout() async {
        await MainActor.run {
            isDeleting = true
        }

        // Delete photos from Firebase first
        if !workout.photos.isEmpty {
            let photoService = PhotoService()
            do {
                try await photoService.deletePhotos(workout.photos)
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
                return // Don't delete the workout
            } catch {
                print("❌ Failed to delete photos from Firebase: \(error)")
                await MainActor.run {
                    isDeleting = false
                    showingDeleteConfirmation = false
                    deleteErrorMessage = "Failed to delete photos from cloud storage. Please check your internet connection and try again."
                    showingDeleteError = true
                    HapticsManager.shared.trigger(.error)
                }
                return // Don't delete the workout
            }
        }

        // Only delete workout if photo deletion succeeded
        modelContext.delete(workout)
        do {
            try modelContext.save()

            // Recalculate PRs after deletion since the deleted workout may have held a PR
            let settingsManager = SettingsManager.shared
            try PersonalRecordService.recalculateAllPersonalRecords(
                modelContext: modelContext,
                measurementSystem: settingsManager.measurementSystem,
                stepHeight: settingsManager.stepHeight
            )

            await MainActor.run {
                isDeleting = false
                showingDeleteConfirmation = false
                HapticsManager.shared.trigger(.success)
                dismiss() // Navigate back to workout list
            }
        } catch {
            print("❌ Error deleting workout: \(error)")
            await MainActor.run {
                isDeleting = false
                showingDeleteConfirmation = false
                deleteErrorMessage = "Failed to delete workout from local storage. Please try again."
                showingDeleteError = true
                HapticsManager.shared.trigger(.error)
            }
        }
    }
}

struct SingleWorkoutDeleteConfirmationView: View {
    let workout: Workout
    let isLoading: Bool
    let isCancelling: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Delete Workout")
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Text("Are you sure you want to delete \"\(workout.name)\"? This action cannot be undone.")
                    .font(.montserratRegular(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .gray)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                // Cancel button - enabled during loading so user can cancel
                Button {
                    onCancel()
                } label: {
                    if isCancelling {
                        HStack(spacing: 6) {
                            ProgressView()
                                .tint(effectiveColorScheme == .dark ? .white : .black)
                                .scaleEffect(0.8)
                            Text("Stopping...")
                        }
                    } else {
                        Text("Cancel")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1))
                )
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                .disabled(isCancelling)
                .opacity(isLoading && !isCancelling ? 0.7 : 1)

                Button {
                    onConfirm()
                } label: {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Delete")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.red)
                )
                .foregroundStyle(.white)
                .disabled(isLoading || isCancelling)
            }
        }
        .padding(20)
        .themedBackground()
    }
}

// MARK: - Preview
#Preview {
    let sampleWorkout = Workout(
        name: "Morning Stair Climb",
        date: Date(),
        duration: 1800, // 30 minutes
        steps: 2500,
        floors: 156,
        stepsPerFloor: 16,
        notes: "Great morning workout! Felt really strong and maintained a good pace throughout the entire session.",
        avgHeartRate: 145,
        maxHeartRate: 165,
        caloriesBurned: 320,
        effortRating: 4.0
    )
    
    WorkoutDetailView(workout: sampleWorkout)
}

#Preview("No Health Metrics") {
    let sampleWorkout = Workout(
        name: "Evening Floors Session",
        date: Date().addingTimeInterval(-86400), // Yesterday
        duration: 2400, // 40 minutes
        steps: 1360,
        floors: 85,
        stepsPerFloor: 16,
        notes: "",
        avgHeartRate: nil,
        maxHeartRate: nil,
        caloriesBurned: nil,
        effortRating: 3.0
    )
    
    WorkoutDetailView(workout: sampleWorkout)
        .preferredColorScheme(.dark)
}
