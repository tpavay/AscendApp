//
//  WorkoutDetailView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/28/25.
//

import SwiftData
import SwiftUI
import UIKit

struct WorkoutDetailView: View {
    let workout: Workout
    private let embedsInNavigationStack: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationViewModel.self) private var authVM
    @Query(sort: \BestEffortCacheEntry.sortKey) private var bestEffortCacheEntries: [BestEffortCacheEntry]
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared
    @State private var showingEditWorkout = false
    @State private var showingShareWorkoutView = false
    @State private var showingDeleteConfirmation = false
    @State private var showingDeleteError = false
    @State private var deleteErrorMessage = ""
    @State private var isDeleting = false
    @State private var isCancelling = false
    @State private var deleteTask: Task<Void, Never>? = nil
    @State private var copyConfirmationTask: Task<Void, Never>? = nil
    @State private var showingLiveClimbSummaryPreview = false
    /// The frozen standing this climb's share card asserts. Read when the composer opens, through
    /// `CompletedClimbRankService`, which is the same source the completion summary reads.
    @State private var shareStanding: SavedClimbShareStanding?
    /// Which workout `shareStanding` belongs to. Keyed by id rather than a bare flag so a reused
    /// view showing a different climb cannot share the previous climb's rank.
    @State private var shareStandingWorkoutId: UUID?
    @State private var copyConfirmationText: String?
    @State private var enrichmentService = AppleHealthEnrichmentService.shared

    // Media layout state
    @State private var sheetPosition: SheetPosition = .middle
    @State private var currentPhotoIndex: Int = 0
    @State private var selectedPhoto: Photo? = nil
    @State private var sheetOffset: CGFloat = 0

    // Scroll tracking for traditional layout nav bar title
    @State private var scrolledPastTitle = false

    /// Scroll distance at which the inline title has passed behind the header and
    /// the nav bar takes over showing it.
    static let navigationTitleRevealOffset: CGFloat = 100

    /// Whether the nav bar should show the title, as a pure function of how far the
    /// content has scrolled. Keeping the rule here rather than inline in the scroll
    /// handler is what lets a test feed it a whole scroll trace and count how many
    /// times the answer - and therefore the state write - actually changes.
    static func revealsNavigationTitle(scrolledDistance: CGFloat) -> Bool {
        scrolledDistance > navigationTitleRevealOffset
    }

    init(workout: Workout, embedsInNavigationStack: Bool = true) {
        self.workout = workout
        self.embedsInNavigationStack = embedsInNavigationStack
    }

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
        if embedsInNavigationStack {
            NavigationStack {
                content
            }
        } else {
            content
        }
    }

    private var content: some View {
        // Resolved once here and threaded down, so a render pass decodes the
        // headphone-motion metadata and the heart-rate blob once apiece instead of
        // once per reader. See `WorkoutDetailDerivedContent`.
        let derived = WorkoutDetailDerivedContent(workout: workout)

        return ZStack {
            (effectiveColorScheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()

            if hasMedia {
                workoutMediaLayout(derived)
            } else {
                traditionalLayout(derived)
            }
        }
        .navigationBarHidden(true)
        .overlay(alignment: .top) {
            adaptiveHeader(derived)
        }
        .sheet(isPresented: $showingEditWorkout) {
            EditWorkoutView(
                workout: workout,
                showingEditWorkout: $showingEditWorkout
            )
            .interactiveDismissDisabled()
        }
        .fullScreenCover(isPresented: $showingShareWorkoutView) {
            ShareComposerView(
                workout: workout,
                climb: liveClimbDetailClimb,
                climbRank: shareStanding?.rank,
                climbRankTotal: shareStanding?.totalClimbers
            )
            // The composer opens on the frame it was asked for and adopts the standing when it
            // lands, so an offline device still gets a composer and no climber waits on a read.
            .task { await resolveShareStandingIfNeeded() }
        }
        .fullScreenCover(isPresented: $showingLiveClimbSummaryPreview) {
            if liveClimbSummaryMetadata?.climbId == nil || liveClimbDetailClimb != nil {
                // The summary owns rank resolution, including the current-basis fallback this
                // screen deliberately has no copy of: recomputing a rank here would be the second,
                // disagreeing source the leaderboard audit flagged, and would refetch on every
                // open. What this screen does read is the frozen snapshot, through the one shared
                // read path both surfaces use - see `SavedClimbShareStanding`.
                LiveClimbCompletionSummaryView(
                    climb: liveClimbDetailClimb,
                    workout: workout,
                    leaderboardRank: nil,
                    leaderboardTotal: nil,
                    leaderboardRankBasis: .current,
                    leaderboardContext: liveClimbSummaryLeaderboardContext,
                    rankingLabelOverride: liveClimbSummaryRankingLabelOverride,
                    ranksOnLeaderboard: liveClimbSummaryLeaderboardContext != nil,
                    onDone: { _ in
                        showingLiveClimbSummaryPreview = false
                    }
                )
            } else {
                LiveClimbSummaryPreviewUnavailableView {
                    showingLiveClimbSummaryPreview = false
                }
            }
        }
        .onAppear {
            if hasMedia {
                currentPhotoIndex = 0
            }
        }
        .task(id: workout.id) {
            // Opening a climb is a climber asking about it, so it re-arms the shared schedule
            // rather than running its own retry loop - the screen is one more surface onto the
            // same series, not a second one racing it.
            enrichmentService.resumeTracking(modelContext: modelContext)
        }
        .onDisappear {
            copyConfirmationTask?.cancel()
            copyConfirmationTask = nil
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
        .overlay(alignment: .top) {
            copyConfirmationOverlay
        }
        // On `content` rather than on `body`, because `body` branches on
        // `embedsInNavigationStack` and only this side is rendered either way.
        .trackOnce(screen: .workoutDetail)
    }

    // MARK: - Media Layout

    @ViewBuilder
    private func workoutMediaLayout(_ derived: WorkoutDetailDerivedContent) -> some View {
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
                    sheetDetailContent(derived)
                }
            }
        }
    }

    private func sheetDetailContent(_ derived: WorkoutDetailDerivedContent) -> some View {
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

                workoutContentSections(derived)
            }
            .padding(.horizontal, 20)
            .padding(.top, sheetPosition == .expanded ? 60 : 8)
        }
    }

    // MARK: - Traditional Layout (No Media)

    private func traditionalLayout(_ derived: WorkoutDetailDerivedContent) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Title row - scrolls naturally behind the opaque nav bar
                WorkoutTitleRow(
                    workoutName: workout.name,
                    dateText: formatWorkoutDateTime(),
                    weightSummary: weightSummary,
                    bestEfforts: workoutBestEfforts,
                    effectiveColorScheme: effectiveColorScheme
                )
                .padding(.top, 80) // Account for header overlay

                // Media upload status banner
                MediaUploadBanner(workoutId: workout.id) {
                    Task {
                        await MediaUploadManager.shared.retryFailedUploads(
                            for: workout.id,
                            modelContext: modelContext
                        )
                    }
                }

                workoutContentSectionsWithoutTitle(derived)

                // Photos section
                WorkoutPhotosSection(workout: workout)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        // Reduces the scroll to the one bit the header cares about, so the action
        // fires on the two threshold crossings rather than on every scroll tick.
        // The GeometryReader overlay this replaces re-resolved the content's global
        // frame every frame to store an offset nothing read.
        .onScrollGeometryChange(for: Bool.self) { geometry in
            Self.revealsNavigationTitle(
                scrolledDistance: geometry.contentOffset.y + geometry.contentInsets.top
            )
        } action: { _, shouldReveal in
            scrolledPastTitle = shouldReveal
        }
    }

    // MARK: - Shared Content Sections

    /// All content sections (used in sheet detail for media layout)
    private func workoutContentSections(_ derived: WorkoutDetailDerivedContent) -> some View {
        Group {
            // Hide inline title when sheet is expanded (nav bar shows it instead)
            if sheetPosition != .expanded {
                WorkoutTitleRow(
                    workoutName: workout.name,
                    dateText: formatWorkoutDateTime(),
                    weightSummary: weightSummary,
                    bestEfforts: workoutBestEfforts,
                    effectiveColorScheme: effectiveColorScheme
                )

            }

            workoutContentSectionsWithoutTitle(derived)

            Spacer(minLength: 40)
        }
    }

    /// Content sections after the title (shared between both layouts)
    private func workoutContentSectionsWithoutTitle(_ derived: WorkoutDetailDerivedContent) -> some View {
        Group {
            // Above the stats on purpose. Whether this climb reached the climber's account is not
            // a footnote about the session - it is whether the session exists anywhere but here.
            WorkoutSyncStatusSection(
                workout: workout,
                effectiveColorScheme: effectiveColorScheme
            )

            // Notes (blockquote style)
            if !workout.notes.isEmpty {
                NotesBlockquote(
                    text: workout.notes,
                    effectiveColorScheme: effectiveColorScheme
                )
            }

            HeroStatsPair(
                leftLabel: "Duration",
                leftValue: workout.durationFormatted,
                rightLabel: "Steps",
                rightValue: formattedPrimaryMetric,
                effectiveColorScheme: effectiveColorScheme
            )

            // Secondary stats row (pace, calories, METs)
            if !secondaryStatItems.isEmpty {
                SecondaryStatsRow(
                    items: secondaryStatItems,
                    effectiveColorScheme: effectiveColorScheme
                )
            }

            if derived.canOpenLiveClimbSummary {
                LiveClimbSummaryLinkRow(
                    climb: liveClimbDetailClimb,
                    effectiveColorScheme: effectiveColorScheme,
                    onViewSummary: {
                        showingLiveClimbSummaryPreview = true
                    }
                )
            }

            heartRateSectionIfNeeded(derived)

            if derived.showsPaceSplits {
                WorkoutPaceSplitsSection(
                    splits: derived.paceSplits,
                    averageStepsPerMinute: workout.stepsPerMinute,
                    effectiveColorScheme: effectiveColorScheme
                )
            }

            // Vertical Climb
            if let verticalClimb = verticalClimbValue {
                VerticalClimbCard(
                    value: verticalClimb.formatted(.number.precision(.fractionLength(1))),
                    unit: workout.verticalClimbUnit(measurementSystem: settingsManager.measurementSystem),
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

    private func adaptiveHeader(_ derived: WorkoutDetailDerivedContent) -> some View {
        VStack(spacing: 0) {
            HStack {
                OnboardingBackButton {
                    dismiss()
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
                    menuContent(derived)
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
    private func menuContent(_ derived: WorkoutDetailDerivedContent) -> some View {
        Button(action: {
            showingShareWorkoutView = true
        }) {
            Label("Share", systemImage: "square.and.arrow.up")
        }

        Button(action: copyWorkoutText) {
            Label("Copy Workout Text", systemImage: "doc.on.doc")
        }

        if derived.canOpenLiveClimbSummary {
            Button {
                showingLiveClimbSummaryPreview = true
            } label: {
                Label("View Completion Summary", systemImage: "flag.checkered")
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

    @MainActor
    private var liveClimbDetailClimb: Climb? {
        LiveClimbWorkoutSummaryData.climb(for: workout)
    }

    private var liveClimbSummaryMetadata: HeadphoneMotionWorkoutMetadata? {
        LiveClimbWorkoutSummaryData.metadata(for: workout)
    }

    @MainActor
    private var liveClimbSummaryLeaderboardContext: LiveReplayLeaderboardContext? {
        LiveClimbWorkoutSummaryData.leaderboardContext(
            metadata: liveClimbSummaryMetadata,
            resolvedClimbId: liveClimbDetailClimb?.id,
            climbTargetSteps: liveClimbDetailClimb?.referenceStepCount,
            workoutSteps: workout.steps
        )
    }

    private var liveClimbSummaryRankingLabelOverride: String? {
        liveClimbSummaryMetadata?.trackingMode == .routine ? "ROUTINE RANK" : nil
    }

    /// Reads the workout's frozen standing so the share composer can offer the rank clusters,
    /// stickers and the recap card's rank tab from this screen, not only from the completion
    /// summary.
    ///
    /// Runs when the composer opens rather than when the screen does, so a session the server
    /// ranks nowhere - a Just Climb, a routine - costs nothing to look at. At most one read per
    /// workout per install: a stored snapshot answers without a request, and
    /// `shareStandingWorkoutId` stops a re-open from asking again for a workout already answered,
    /// while still admitting a different one. The service ignores cancellation, so the id is
    /// re-checked after the await: a resolve for the climb this view used to show must not land on
    /// the one it shows now.
    @MainActor
    private func resolveShareStandingIfNeeded() async {
        let resolvingWorkoutId = workout.id
        guard shareStandingWorkoutId != resolvingWorkoutId else { return }

        shareStanding = nil
        shareStandingWorkoutId = resolvingWorkoutId
        guard let context = liveClimbSummaryLeaderboardContext else { return }

        let resolved = await SavedClimbShareStanding.resolve(
            context: context,
            workoutId: resolvingWorkoutId.uuidString
        )
        guard shareStandingWorkoutId == resolvingWorkoutId else { return }
        shareStanding = resolved
    }

    /// A climb either has heart-rate data to show or this section does not exist. Enrichment still
    /// runs in the background and adding samples invalidates the model, so the chart appears as
    /// soon as data lands without narrating the wait.
    @ViewBuilder
    private func heartRateSectionIfNeeded(_ derived: WorkoutDetailDerivedContent) -> some View {
        if derived.heartRateSeries.isEmpty == false {
            HeartRateChartView(
                heartRateData: derived.heartRateSeries,
                workoutStartTime: workout.date,
                workoutDuration: workout.duration,
                averageHeartRateBpm: workout.avgHeartRate,
                maxHeartRateBpm: workout.maxHeartRate
            )
        } else if shouldShowRemoteHeartRateRestore(derived) {
            WorkoutHeartRateRestoreCard(
                status: workout.heartRateRestoreStatus,
                effectiveColorScheme: effectiveColorScheme,
                onRetry: retryRemoteHeartRateRestore
            )
        }
    }

    private func shouldShowRemoteHeartRateRestore(_ derived: WorkoutDetailDerivedContent) -> Bool {
        workout.lastRemoteHeartRateSeriesStoragePath != nil &&
            derived.heartRateSeries.isEmpty &&
            workout.heartRateRestoreStatus.treatsLocalAbsenceAsAuthoritative == false
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

    private var formattedPrimaryMetric: String {
        workout.steps.formatted(.number)
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

        if let pace = workout.stepsPerMinute {
            items.append(SecondaryStatItem(
                label: "steps/Min",
                value: pace.formatted(.number.precision(.fractionLength(1)))
            ))
        }

        // Calories
        if let calories = workout.caloriesBurned {
            items.append(SecondaryStatItem(
                label: "Calories",
                value: "\(calories)"
            ))
        }

        // METs
        if let mets = workout.averageMETs {
            items.append(SecondaryStatItem(
                label: "METs",
                value: mets.formatted(.number.precision(.fractionLength(1)))
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

    private var workoutBestEfforts: [RankedBestEffort] {
        BestEffortCacheSnapshot(
            entries: bestEffortCacheEntries,
            workouts: [workout]
        )
        .efforts(for: workout)
    }

    private var primaryBestEffort: RankedBestEffort? {
        workoutBestEfforts.first
    }

    @ViewBuilder
    private var copyConfirmationOverlay: some View {
        if let copyConfirmationText {
            Text(copyConfirmationText)
                .font(.montserratSemiBold(size: 14))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Capsule().fill(.black.opacity(0.82)))
                .padding(.top, 72)
                .transition(.opacity.combined(with: .scale))
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

    private func copyWorkoutText() {
        UIPasteboard.general.string = workoutShareText(
            for: workout,
            measurementSystem: settingsManager.measurementSystem,
            stepHeight: settingsManager.stepHeight,
            bestEffort: primaryBestEffort
        )
        HapticsManager.shared.trigger(.success)
        showCopyConfirmation("Workout text copied")
    }

    private func showCopyConfirmation(_ text: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            copyConfirmationText = text
        }

        copyConfirmationTask?.cancel()
        copyConfirmationTask = Task {
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                if copyConfirmationText == text {
                    copyConfirmationText = nil
                }
            }
        }
    }

    private func retryRemoteHeartRateRestore() {
        guard let userId = workout.ownerUserId else { return }

        Task { @MainActor in
            let previousStatus = workout.heartRateRestoreStatus
            let previousErrorCode = workout.heartRateRestoreErrorCode
            workout.heartRateRestoreStatus = .pending
            try? modelContext.save()

            _ = try? await WorkoutHydrationService.hydrateIfNeeded(
                modelContext: modelContext,
                currentUserId: userId
            )

            // Hydration always leaves a terminal status behind. Still `.pending` means it never got
            // as far as this workout, so the card must not be stranded without a retry affordance.
            guard workout.heartRateRestoreStatus == .pending else { return }

            workout.heartRateRestoreStatus = previousStatus
            workout.heartRateRestoreErrorCode = previousErrorCode
            try? modelContext.save()
        }
    }

    private func deleteWorkout() async {
        guard !workout.isLiveClimbAttemptWorkout else {
            await MainActor.run {
                showingDeleteConfirmation = false
                deleteErrorMessage = "Live Climb attempts are saved as competitive history and cannot be deleted."
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
                debugLog("❌ Failed to delete photos: \(error)")
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
                debugLog("❌ Failed to delete photos from Firebase: \(error)")
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
            debugLog("❌ Error queueing remote workout deletion: \(error)")
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
            debugLog("❌ Error deleting workout: \(error)")

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
        effortRating: 4.0,
        source: .headphoneMotion
    )

    WorkoutDetailView(workout: sampleWorkout)
        .modelContainer(
            for: [
                Workout.self,
                WorkoutSourceLink.self,
                WorkoutParticipation.self,
                BestEffortCacheEntry.self,
                BestEffortCacheMetadata.self
            ],
            inMemory: true
        )
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
        effortRating: 3.0,
        source: .headphoneMotion
    )

    WorkoutDetailView(workout: sampleWorkout)
        .preferredColorScheme(.dark)
        .modelContainer(
            for: [
                Workout.self,
                WorkoutSourceLink.self,
                WorkoutParticipation.self,
                BestEffortCacheEntry.self,
                BestEffortCacheMetadata.self
            ],
            inMemory: true
        )
}
