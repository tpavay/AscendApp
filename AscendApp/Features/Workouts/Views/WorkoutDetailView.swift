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
#if DEBUG
    @State private var showingLiveClimbSummaryPreview = false
#endif

    // Strava-style layout state
    @State private var sheetPosition: SheetPosition = .middle
    @State private var currentPhotoIndex: Int = 0
    @State private var selectedPhoto: Photo? = nil
    @State private var sheetOffset: CGFloat = 0

    // Scroll tracking for traditional layout nav bar title
    @State private var scrolledPastTitle = false
    @State private var scrollContentOffset: CGFloat = 0

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var hasMedia: Bool {
        !orderedPhotos.isEmpty
    }

    private var orderedPhotos: [Photo] {
        workout.orderedPhotosForDisplay
    }

    var body: some View {
        NavigationStack {
            ZStack {
                (effectiveColorScheme == .dark ? Color.black : Color.white)
                    .ignoresSafeArea()

                if hasMedia {
                    stravaStyleLayout
                } else {
                    traditionalLayout
                }
            }
            .navigationBarHidden(true)
            .overlay(alignment: .top) {
                adaptiveHeader
            }
            .sheet(isPresented: $showingEditWorkout) {
                EditWorkoutView(
                    workout: workout,
                    showingEditWorkout: $showingEditWorkout
                )
                .interactiveDismissDisabled()
            }
            .sheet(isPresented: $showingShareWorkoutView) {
                WorkoutShareCarouselView(workout: workout)
            }
#if DEBUG
            .fullScreenCover(isPresented: $showingLiveClimbSummaryPreview) {
                if let climb = liveClimbSummaryPreviewClimb {
                    LiveClimbCompletionSummaryView(
                        climb: climb,
                        workout: workout,
                        leaderboardRank: nil,
                        leaderboardTotal: nil,
                        onDone: {
                            showingLiveClimbSummaryPreview = false
                        }
                    )
                } else {
                    LiveClimbSummaryPreviewUnavailableView {
                        showingLiveClimbSummaryPreview = false
                    }
                }
            }
#endif
            .onAppear {
                if hasMedia {
                    currentPhotoIndex = 0
                }
            }
            .onChange(of: showingEditWorkout) { _, isShowing in
                if !isShowing && hasMedia {
                    currentPhotoIndex = 0
                }
            }
            .sheet(isPresented: $showingDeleteConfirmation) {
                SingleWorkoutDeleteConfirmationView(
                    workout: workout,
                    isLoading: isDeleting,
                    isCancelling: isCancelling,
                    onConfirm: {
                        guard deleteTask == nil else { return }
                        deleteTask = Task {
                            await deleteWorkout()
                            deleteTask = nil
                        }
                    },
                    onCancel: {
                        if isDeleting {
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
            .fullScreenCover(item: $selectedPhoto) { photo in
                FullScreenPhotoView(photo: photo) {
                    selectedPhoto = nil
                }
            }
        }
    }

    // MARK: - Strava-Style Layout (unchanged structure, new content)

    @ViewBuilder
    private var stravaStyleLayout: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                let heroHeight = sheetOffset > 0 ? sheetOffset : sheetPosition.photoHeight(in: geometry)
                let heroOpacity: Double = {
                    if sheetOffset > 0 {
                        return min(1.0, sheetOffset / (geometry.size.height * 0.1))
                    } else {
                        return sheetPosition.photoOpacity
                    }
                }()

                WorkoutDetailHeroView(
                    photos: orderedPhotos,
                    currentIndex: $currentPhotoIndex,
                    sheetPosition: sheetPosition,
                    isPlaybackEnabled: selectedPhoto == nil,
                    onPhotoTap: { photo in
                        selectedPhoto = photo
                    }
                )
                .frame(height: heroHeight)
                .opacity(heroOpacity)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: sheetPosition)

                DraggableDetailSheet(position: $sheetPosition, currentOffset: $sheetOffset) {
                    sheetDetailContent(in: geometry)
                }
            }
        }
    }

    private func sheetDetailContent(in geometry: GeometryProxy) -> some View {
        ScrollableDetailContent(sheetPosition: $sheetPosition) {
            VStack(spacing: 24) {
                MediaUploadBanner(workoutId: workout.id) {
                    Task {
                        await MediaUploadManager.shared.retryFailedUploads(
                            for: workout.id,
                            modelContext: modelContext
                        )
                    }
                }

                workoutContentSections
            }
            .padding(.horizontal, 20)
            .padding(.top, sheetPosition == .expanded ? 60 : 8)
        }
    }

    // MARK: - Traditional Layout (No Media)

    private var traditionalLayout: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Title row — scrolls naturally behind the opaque nav bar
                WorkoutTitleRow(
                    workoutName: workout.name,
                    dateText: formatWorkoutDateTime(),
                    weightSummary: weightSummary,
                    prCount: workout.totalPRCount,
                    prDetails: prDetails,
                    effectiveColorScheme: effectiveColorScheme
                )
                .padding(.top, 80) // Account for header overlay

                // Strava sync indicator
                if FeatureFlags.isStravaEnabled && (isSyncingToStrava || workout.isSyncedToStrava) {
                    stravaSyncBadge
                }

                // Media upload status banner
                MediaUploadBanner(workoutId: workout.id) {
                    Task {
                        await MediaUploadManager.shared.retryFailedUploads(
                            for: workout.id,
                            modelContext: modelContext
                        )
                    }
                }

                workoutContentSectionsWithoutTitle

                // Photos section
                WorkoutPhotosSection(workout: workout)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .overlay(alignment: .top) {
                // Scroll offset tracker — pinned to top of content
                GeometryReader { geo in
                    let minY = geo.frame(in: .global).minY
                    Color.clear
                        .onChange(of: minY) { _, newValue in
                            scrollContentOffset = newValue
                            // Title text is at ~96pt from content top (16pt padding + 80pt offset).
                            // When the content top (minY) has scrolled so the title is behind the
                            // nav bar, show the nav bar title. The safe area top + nav bar ≈ 100pt.
                            let shouldShow = newValue < -40
                            if shouldShow != scrolledPastTitle {
                                scrolledPastTitle = shouldShow
                            }
                        }
                }
                .frame(height: 0)
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Shared Content Sections

    /// All content sections (used in sheet detail for media layout)
    private var workoutContentSections: some View {
        Group {
            // Hide inline title when sheet is expanded (nav bar shows it instead)
            if sheetPosition != .expanded {
                WorkoutTitleRow(
                    workoutName: workout.name,
                    dateText: formatWorkoutDateTime(),
                    weightSummary: weightSummary,
                    prCount: workout.totalPRCount,
                    prDetails: prDetails,
                    effectiveColorScheme: effectiveColorScheme
                )

                if FeatureFlags.isStravaEnabled && (isSyncingToStrava || workout.isSyncedToStrava) {
                    stravaSyncBadge
                }
            }

            workoutContentSectionsWithoutTitle

            Spacer(minLength: 40)
        }
    }

    /// Content sections after the title (shared between both layouts)
    private var workoutContentSectionsWithoutTitle: some View {
        Group {
            // Notes (blockquote style)
            if !workout.notes.isEmpty {
                NotesBlockquote(
                    text: workout.notes,
                    effectiveColorScheme: effectiveColorScheme
                )
            }

            // Hero stats: Duration + Steps/Floors
            HeroStatsPair(
                leftLabel: "Duration",
                leftValue: workout.durationFormatted,
                rightLabel: preferredMetric.displayName,
                rightValue: formattedPrimaryMetric,
                leftIsPR: isStatAPR(.duration),
                rightIsPR: isStatAPR(preferredMetric == .steps ? .steps : .floors),
                effectiveColorScheme: effectiveColorScheme
            )

            // Secondary stats row (pace, calories, METs)
            if !secondaryStatItems.isEmpty {
                SecondaryStatsRow(
                    items: secondaryStatItems,
                    effectiveColorScheme: effectiveColorScheme
                )
            }

            // Heart Rate Chart
            if !workout.heartRateTimeSeries.isEmpty {
                HeartRateChartView(
                    heartRateData: workout.heartRateTimeSeries,
                    workoutStartTime: workout.date,
                    workoutDuration: workout.duration
                )
            }

            // Vertical Climb
            if let verticalClimb = verticalClimbValue {
                VerticalClimbCard(
                    value: verticalClimb.formatted(.number.precision(.fractionLength(1))),
                    unit: workout.verticalClimbUnit(measurementSystem: settingsManager.measurementSystem),
                    isPR: isStatAPR(.verticalClimb),
                    effectiveColorScheme: effectiveColorScheme
                )
            }

            // Effort Rating
            if let effortRating = workout.effortRating {
                EffortRatingCard(
                    rating: effortRating,
                    effectiveColorScheme: effectiveColorScheme
                )
            }

            // Weights section (unchanged)
            if workout.hasWeights {
                weightsUsedSection
            }
        }
    }

    // MARK: - Adaptive Header

    private var adaptiveHeader: some View {
        VStack(spacing: 0) {
            HStack {
                // Back button
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(headerForegroundColor)
                        .padding(10)
                        .background(
                            Circle()
                                .fill(headerBackgroundColor)
                        )
                }

                Spacer()

                // Title + subtitle (fades in when scrolled past inline title)
                VStack(spacing: 2) {
                    Text(workout.name)
                        .font(.montserratSemiBold(size: 16))
                        .foregroundStyle(headerForegroundColor)
                        .lineLimit(1)

                    Text(headerSubtitleText)
                        .font(.montserratRegular(size: 11))
                        .foregroundStyle(headerForegroundColor.opacity(0.6))
                        .lineLimit(1)
                }
                .opacity(headerTitleOpacity)

                Spacer()

                // Menu button
                Menu {
                    menuContent
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(headerForegroundColor)
                        .padding(10)
                        .background(
                            Circle()
                                .fill(headerBackgroundColor)
                        )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, hasMedia && sheetPosition != .expanded ? 8 : 16)

            if !hasMedia || sheetPosition == .expanded {
                Divider()
                    .background(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))
            }
        }
        .background {
            headerBackground
                .ignoresSafeArea(edges: .top)
        }
        .animation(.easeOut(duration: 0.2), value: sheetPosition)
        .animation(.easeOut(duration: 0.2), value: scrolledPastTitle)
    }

    private var headerForegroundColor: Color {
        if hasMedia && sheetPosition != .expanded {
            return .white
        }
        return effectiveColorScheme == .dark ? .white : .black
    }

    private var headerBackgroundColor: Color {
        if hasMedia && sheetPosition != .expanded {
            return Color.black.opacity(0.3)
        }
        return .clear
    }

    private var headerTitleOpacity: Double {
        if hasMedia {
            return sheetPosition == .expanded ? 1.0 : 0.0
        } else {
            return scrolledPastTitle ? 1.0 : 0.0
        }
    }

    @ViewBuilder
    private var headerBackground: some View {
        if hasMedia && sheetPosition != .expanded {
            Color.clear
        } else {
            effectiveColorScheme == .dark ? Color.black : Color.white
        }
    }

    /// Compact subtitle text for the nav bar (date + optional weight)
    private var headerSubtitleText: String {
        let date = formatWorkoutDateTime()
        switch weightSummary {
        case .none:
            return date
        case .single(let label):
            return "\(date) | \(label)"
        case .multiple(let total, _):
            return "\(date) | +\(total)"
        }
    }

    // MARK: - Menu

    @ViewBuilder
    private var menuContent: some View {
        Button(action: {
            showingShareWorkoutView = true
        }) {
            Label("Share", systemImage: "square.and.arrow.up")
        }

#if DEBUG
        if canPreviewLiveClimbSummary {
            Button {
                showingLiveClimbSummaryPreview = true
            } label: {
                Label("Preview Completion Summary", systemImage: "flag.checkered")
            }
        }
#endif

        if FeatureFlags.isStravaEnabled && stravaManager.isConnected {
            if workout.isSyncedToStrava {
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

        if workout.isLiveClimbAttemptWorkout {
            Label("Live climb result locked", systemImage: "lock.fill")
        } else {
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
        }
    }

#if DEBUG
    private var canPreviewLiveClimbSummary: Bool {
        LiveClimbWorkoutSummaryData.metadata(for: workout)?.climbId != nil
    }

    @MainActor
    private var liveClimbSummaryPreviewClimb: Climb? {
        LiveClimbWorkoutSummaryData.climb(for: workout)
    }
#endif

    // MARK: - Strava Sync Badge

    private var stravaSyncBadge: some View {
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
        .foregroundStyle(Color(red: 252/255, green: 76/255, blue: 2/255))
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

    // MARK: - Weights Section (unchanged)

    private var weightsUsedSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Weights Used")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                Spacer()
            }

            VStack(spacing: 0) {
                if let config = workout.weightConfiguration {
                    ForEach(Array(config.entries.filter { $0.isEnabled }.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider()
                                .padding(.leading, 48)
                        }
                        weightEntryRow(entry: entry)
                    }

                    Divider()
                        .padding(.vertical, 8)

                    HStack {
                        Text("Total Added Weight")
                            .font(.montserratMedium(size: 15))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                        Spacer()

                        Text(settingsManager.measurementSystem.formatWeight(config.totalWeight))
                            .font(.montserratSemiBold(size: 16))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
            )
        }
    }

    private func weightEntryRow(entry: WeightEntry) -> some View {
        HStack(spacing: 12) {
            weightEquipmentIcon(for: entry.equipmentType)
                .frame(width: 24, height: 24)

            Text(entry.equipmentType.displayName)
                .font(.montserratMedium(size: 15))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.formattedWeight(unit: settingsManager.measurementSystem.weightAbbreviation))
                    .font(.montserratSemiBold(size: 15))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                if entry.equipmentType.isPaired {
                    Text("(\(settingsManager.measurementSystem.formatWeight(entry.totalWeight)) total)")
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                }
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func weightEquipmentIcon(for type: WeightEquipmentType) -> some View {
        if let _ = UIImage(named: type.iconName) {
            Image(type.iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: weightFallbackSFSymbol(for: type))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.accent)
        }
    }

    private func weightFallbackSFSymbol(for type: WeightEquipmentType) -> String {
        switch type {
        case .weightedVest: return "tshirt.fill"
        case .dumbbells: return "dumbbell.fill"
        case .barbell: return "figure.strengthtraining.traditional"
        case .ankleWeights: return "shoe.fill"
        case .wristWeights: return "hand.raised.fill"
        }
    }

    // MARK: - Data Helpers

    private var preferredMetric: WorkoutMetric {
        settingsManager.preferredWorkoutMetric
    }

    private var formattedPrimaryMetric: String {
        let value = workout.metricValue(for: preferredMetric)
        return value.formatted(.number)
    }

    private var verticalClimbValue: Double? {
        workout.totalVerticalClimb(
            stepHeight: settingsManager.stepHeight,
            measurementSystem: settingsManager.measurementSystem
        )
    }

    /// Build secondary stat items from available data
    private var secondaryStatItems: [SecondaryStatItem] {
        var items: [SecondaryStatItem] = []

        // Pace (steps/min or floors/min)
        if let pace = workout.pace(for: preferredMetric) {
            items.append(SecondaryStatItem(
                label: "\(preferredMetric.unit)/Min",
                value: pace.formatted(.number.precision(.fractionLength(1))),
                isPR: isStatAPR(.pace)
            ))
        }

        // Calories
        if let calories = workout.caloriesBurned {
            items.append(SecondaryStatItem(
                label: "Calories",
                value: "\(calories)",
                isPR: isStatAPR(.calories)
            ))
        }

        // METs
        if let mets = workout.averageMETs {
            items.append(SecondaryStatItem(
                label: "METs",
                value: mets.formatted(.number.precision(.fractionLength(1))),
                isPR: false // No PR type for METs
            ))
        }

        return items
    }

    /// Build weight summary for the title row subtitle
    private var weightSummary: WeightSummary {
        guard let config = workout.weightConfiguration, !config.isEmpty else {
            return .none
        }

        let enabledEntries = config.entries.filter { $0.isEnabled }
        let ms = settingsManager.measurementSystem

        if enabledEntries.count == 1, let entry = enabledEntries.first {
            let weightStr = ms.formatWeight(entry.totalWeight)
            let label = "\(weightStr) \(entry.equipmentType.displayName.lowercased())"
            return .single(label: label)
        } else {
            let total = ms.formatWeight(config.totalWeight)
            let entries = enabledEntries.map { entry in
                (name: entry.equipmentType.displayName, weight: ms.formatWeight(entry.totalWeight))
            }
            return .multiple(total: total, entries: entries)
        }
    }

    /// Build the list of all PR details for the trophy badge popover
    private var prDetails: [PRDetail] {
        var details: [PRDetail] = []

        // Standard PRs
        for pr in workout.achievedPersonalRecords {
            details.append(PRDetail(emoji: pr.emoji, name: pr.displayName, isWeightPR: false))
        }

        // Weight PRs (stored as raw string keys)
        if let weightPRKeys = workout.weightPersonalRecordTypes {
            for key in weightPRKeys {
                // Try weight combo record types first
                if let recordType = WeightRecordType(rawValue: key) {
                    details.append(PRDetail(emoji: recordType.emoji, name: recordType.displayName, isWeightPR: true))
                }
                // Then aggregate weight record types
                else if let aggType = AggregateWeightRecordType(rawValue: key) {
                    details.append(PRDetail(emoji: aggType.emoji, name: aggType.displayName, isWeightPR: true))
                }
                // Unknown key — show generic
                else {
                    details.append(PRDetail(emoji: "🏋️", name: key, isWeightPR: true))
                }
            }
        }

        return details
    }

    // MARK: - PR Awareness

    private enum StatIdentifier {
        case duration, steps, floors, pace, avgHeartRate, maxHeartRate, verticalClimb, calories
    }

    private func isStatAPR(_ stat: StatIdentifier) -> Bool {
        let prTypes = workout.achievedPersonalRecords
        let metric = settingsManager.preferredWorkoutMetric
        switch stat {
        case .duration:       return prTypes.contains(.longestDuration)
        case .steps:          return metric == .steps && prTypes.contains(.mostSteps)
        case .floors:         return metric == .floors && prTypes.contains(.mostFloors)
        case .pace:           return prTypes.contains(.highestAveragePace)
        case .avgHeartRate:   return prTypes.contains(.highestAverageHeartRate)
        case .maxHeartRate:   return prTypes.contains(.highestMaxHeartRate)
        case .verticalClimb:  return prTypes.contains(.highestVerticalClimb)
        case .calories:       return prTypes.contains(.mostCaloriesBurned)
        }
    }

    // MARK: - Formatting

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
            if calendar.component(.year, from: workout.date) == calendar.component(.year, from: Date()) {
                dateFormatter.dateFormat = "MMM d"
            } else {
                dateFormatter.dateFormat = "MMM d, yyyy"
            }
            return "\(dateFormatter.string(from: workout.date)) at \(timeFormatter.string(from: workout.date))"
        }
    }

    // MARK: - Actions

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

                let metadata = StravaSyncMetadata(stravaActivityId: activityId)
                workout.setStravaSyncMetadata(metadata)
                try? modelContext.save()

                HapticsManager.shared.trigger(.success)
                showingStravaSyncSuccess = true

                try? await Task.sleep(for: .seconds(2))
                showingStravaSyncSuccess = false
            } catch {
                stravaSyncError = error.localizedDescription
                HapticsManager.shared.trigger(.error)
            }

            isSyncingToStrava = false
        }
    }

    private func deleteWorkout() async {
        guard !workout.isLiveClimbAttemptWorkout else {
            await MainActor.run {
                showingDeleteConfirmation = false
                deleteErrorMessage = "Live climb attempts are saved as competitive history and cannot be deleted from the workout log."
                showingDeleteError = true
            }
            return
        }

        await MainActor.run {
            isDeleting = true
        }

        await MediaUploadManager.shared.cancelUploads(for: workout.id, modelContext: modelContext)

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
                return
            } catch {
                print("❌ Failed to delete photos from Firebase: \(error)")
                await MainActor.run {
                    isDeleting = false
                    showingDeleteConfirmation = false
                    deleteErrorMessage = "Failed to delete photos from cloud storage. Please check your internet connection and try again."
                    showingDeleteError = true
                    HapticsManager.shared.trigger(.error)
                }
                return
            }
        }

        let remoteSyncUserId = workout.ownerUserId ?? authVM.user?.uid
        let didQueueRemoteDeletion: Bool

        do {
            didQueueRemoteDeletion = try WorkoutSyncCoordinator.shared.enqueuePendingDeletions(
                for: [workout],
                fallbackUserId: authVM.user?.uid,
                modelContext: modelContext
            )
        } catch {
            print("❌ Error queueing remote workout deletion: \(error)")
            await MainActor.run {
                isDeleting = false
                showingDeleteConfirmation = false
                deleteErrorMessage = "Failed to prepare workout deletion. Please try again."
                showingDeleteError = true
                HapticsManager.shared.trigger(.error)
            }
            return
        }

        var shouldProcessRemoteDeletion = false

        modelContext.delete(workout)
        do {
            let deletedSnapshot = LeaderboardWorkoutSnapshot(workout: workout)
            try modelContext.save()
            shouldProcessRemoteDeletion = didQueueRemoteDeletion
            try WorkoutMutationHandler.shared.workoutsDidChange(
                modelContext: modelContext,
                mutation: .deleted([deletedSnapshot])
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
                dismiss()
            }
        } catch {
            print("❌ Error deleting workout: \(error)")

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
                deleteErrorMessage = "Failed to delete workout from local storage. Please try again."
                showingDeleteError = true
                HapticsManager.shared.trigger(.error)
            }
        }
    }
}

#if DEBUG
private struct LiveClimbSummaryPreviewUnavailableView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.accent)

            VStack(spacing: 8) {
                Text("Summary unavailable")
                    .font(.montserratBold(size: 22))
                    .foregroundStyle(.white)

                Text("This workout has Live Climb metadata, but its climb could not be loaded.")
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Button(action: onDismiss) {
                Text("Done")
                    .font(.montserratBold(size: 15))
                    .foregroundStyle(.black)
                    .frame(width: 160, height: 48)
                    .background(Capsule().fill(Color.accent))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
#endif

// MARK: - Delete Confirmation

struct SingleWorkoutDeleteConfirmationView: View {
    let workout: Workout
    let isLoading: Bool
    let isCancelling: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ConfirmationView(
            title: "Delete Workout",
            message: "Are you sure you want to delete \"\(workout.name)\"? This action cannot be undone.",
            confirmButtonText: "Delete",
            isDestructive: true,
            isLoading: isLoading,
            isCancelling: isCancelling,
            onCancel: onCancel,
            onConfirm: onConfirm
        )
        .appSheetStyle(.destructiveConfirmation)
    }
}

// MARK: - Preview
#Preview {
    let sampleWorkout = Workout(
        name: "Morning Stair Climb",
        date: Date(),
        duration: 1800,
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
        date: Date().addingTimeInterval(-86400),
        duration: 2400,
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
