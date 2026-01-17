//
//  WorkoutListView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import SwiftUI
import SwiftData
import AVFoundation

/// Represents how the workout form is being presented
enum WorkoutFormPresentation: Identifiable {
    case manual
    case fromScan(ConsoleScanResult)

    var id: String {
        switch self {
        case .manual: return "manual"
        case .fromScan(_): return "scan"
        }
    }

    var prefillResult: ConsoleScanResult? {
        switch self {
        case .manual: return nil
        case .fromScan(let result): return result
        }
    }
}

struct WorkoutListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationViewModel.self) private var authVM
    @State private var themeManager = ThemeManager.shared
    @State private var unifiedImportService = UnifiedImportService.shared
    @State private var settingsManager = SettingsManager.shared
    @StateObject private var filterState = WorkoutListFilterState()
    
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @State private var workoutFormPresentation: WorkoutFormPresentation? = nil
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

    // Console scanner state
    @State private var showingEntrySelection = false
    @State private var showingScanner = false

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
                    selectedCount: selectedWorkouts.count,
                    allSelected: areAllWorkoutsSelected,
                    effectiveColorScheme: effectiveColorScheme,
                    pendingImportCount: unifiedImportService.totalPendingCount,
                    canDelete: !selectedWorkouts.isEmpty,
                    workouts: workouts,
                    filterState: filterState,
                    onToggleSelectAll: toggleSelectAllWorkouts,
                    onCancelDelete: exitDeleteMode,
                    onDeleteTapped: handleDeleteTapped,
                    onImportTapped: handleImportTapped,
                    onEnterDeleteMode: enterDeleteMode
                )

                // Workout count
                if !workouts.isEmpty && !isInDeleteMode {
                    Text("Showing \(filteredWorkouts.count) workout\(filteredWorkouts.count == 1 ? "" : "s")")
                        .font(.montserratMedium(size: 13))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
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
            .navigationBarHidden(true)
            .overlay(alignment: .bottomTrailing) {
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
            .sheet(isPresented: $showingEntrySelection) {
                WorkoutEntrySelectionView(
                    onManualEntry: {
                        showingEntrySelection = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            workoutFormPresentation = .manual
                        }
                    },
                    onScanConsole: {
                        showingEntrySelection = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingScanner = true
                        }
                    },
                    onImportWorkouts: {
                        showingEntrySelection = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            handleImportTapped()
                        }
                    },
                    pendingImportCount: unifiedImportService.totalPendingCount
                )
                .presentationDetents([.height(280)])
            }
            .fullScreenCover(isPresented: $showingScanner) {
                ConsoleScannerContainerView(
                    onScanConfirmed: { result in
                        showingScanner = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            workoutFormPresentation = .fromScan(result)
                        }
                    },
                    onCancel: {
                        showingScanner = false
                    }
                )
            }
            .sheet(item: $workoutFormPresentation) { presentation in
                WorkoutFormView(
                    showingWorkoutForm: Binding(
                        get: { workoutFormPresentation != nil },
                        set: { if !$0 { workoutFormPresentation = nil } }
                    ),
                    onWorkoutCompleted: { workout in
                        print("🔍 WorkoutListView: onWorkoutCompleted called")
                        completedWorkout = workout

                        // Dismiss the form
                        workoutFormPresentation = nil

                        // Then show completed view after a brief delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingCompletedView = true
                            print("🔍 WorkoutListView: Set showingCompletedView = true")
                        }
                    },
                    prefillResult: presentation.prefillResult
                )
                .interactiveDismissDisabled()
            }
            .fullScreenCover(isPresented: $showingCompletedView) {
                if let workout = completedWorkout {
                    WorkoutShareCarouselView(
                        workout: workout,
                        workoutCount: workouts.count,
                        displayName: authVM.displayName,
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
                .presentationDetents([.height(200)])
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
                // Configure unified import service with model context
                unifiedImportService.configure(modelContext: modelContext)
            }
        }
    }
    
    
    private var areAllWorkoutsSelected: Bool {
        !workouts.isEmpty && selectedWorkouts.count == workouts.count
    }
    
    private func toggleSelectAllWorkouts() {
        if areAllWorkoutsSelected {
            selectedWorkouts.removeAll()
        } else {
            selectedWorkouts = Set(workouts.map { $0.id })
        }
    }
    
    private func handleDeleteTapped() {
        if !selectedWorkouts.isEmpty {
            showingDeleteConfirmation = true
        }
    }
    
    private func handleImportTapped() {
        Task {
            await unifiedImportService.checkForNewWorkouts()
            showingImportSheet = true
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

        let workoutsToDelete = workouts.filter { selectedWorkouts.contains($0.id) }

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
        do {
            for workout in workoutsToDelete {
                modelContext.delete(workout)
            }
            try modelContext.save()

            // Recalculate PRs after deletion since a deleted workout may have held a PR
            try PersonalRecordService.recalculateAllPersonalRecords(
                modelContext: modelContext,
                measurementSystem: settingsManager.measurementSystem,
                stepHeight: settingsManager.stepHeight
            )

            await MainActor.run {
                isDeleting = false
                showingDeleteConfirmation = false
                HapticsManager.shared.trigger(.success)
                exitDeleteMode()
            }
        } catch {
            print("❌ Error deleting workouts: \(error)")
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

struct WorkoutRowView: View {
    let workout: Workout
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var preferredMetric: WorkoutMetric {
        settingsManager.preferredWorkoutMetric
    }

    private var formattedDateTime: String {
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"

        if calendar.isDateInToday(workout.date) {
            return "Today at \(timeFormatter.string(from: workout.date))"
        } else if calendar.isDateInYesterday(workout.date) {
            return "Yesterday at \(timeFormatter.string(from: workout.date))"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d, yyyy"
            return "\(dateFormatter.string(from: workout.date)) at \(timeFormatter.string(from: workout.date))"
        }
    }

    private var paceText: String? {
        guard let pace = workout.pace(for: preferredMetric) else { return nil }
        let unit = preferredMetric == .steps ? "spm" : "fpm"
        return "\(Int(pace)) \(unit)"
    }

    /// Formats metric value compactly for large numbers (100K+)
    private var compactMetricValue: String {
        let value = workout.metricValue(for: preferredMetric)
        if value >= 100_000 {
            // Round to nearest hundred, then format as K
            let rounded = (Double(value) / 100).rounded() * 100
            let inK = rounded / 1000
            // Remove trailing .0 if whole number
            if inK.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(inK))K"
            } else {
                return String(format: "%.1fK", inK)
            }
        } else {
            return value.formatted()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Title (left) + Date/Time/Strava (right)
            HStack(alignment: .top, spacing: 8) {
                Text(workout.name)
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                HStack(spacing: 6) {
                    Text(formattedDateTime)
                        .font(.montserratRegular(size: 11))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)

                    if FeatureFlags.isStravaEnabled && workout.isSyncedToStrava {
                        Image("strava-icon")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                            .foregroundStyle(Color(red: 252/255, green: 76/255, blue: 2/255))
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            // Separator line
            Rectangle()
                .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))
                .frame(height: 1)

            // Main stats row
            HStack(spacing: 6) {
                // Primary metric
                Text("\(compactMetricValue) \(preferredMetric.unit)")
                    .font(.montserratBold(size: 18))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Text("•")
                    .font(.system(size: 10))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.4) : .gray.opacity(0.6))

                // Duration
                Text(workout.durationFormatted)
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)

                if let pace = paceText {
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.4) : .gray.opacity(0.6))
                    Text(pace)
                        .font(.montserratMedium(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                }

                Spacer()

                // Weight indicator badge (if weights were used)
                if workout.hasWeights {
                    WeightIndicatorBadge(size: .small)
                }

                // Personal Records pill - aligned right
                if workout.hasPersonalRecords {
                    let prCount = workout.achievedPersonalRecords.count
                    Text("🏆 \(prCount)")
                        .font(.montserratSemiBold(size: 12))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(.accent)
                        )
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            // Notes section
            if !workout.notes.isEmpty {
                Text(workout.notes)
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Photo/Video section
            if !workout.photos.isEmpty {
                WorkoutCardMediaSection(workout: workout)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1.5)
                )
        )
    }
}

/// Media section for workout cards - handles single full-width or carousel for multiple
struct WorkoutCardMediaSection: View {
    let workout: Workout

    private var sortedPhotos: [Photo] {
        // Put highlighted photo first, then the rest
        var photos = workout.photos
        if let highlightedId = workout.highlightedPhotoId,
           let highlightedIndex = photos.firstIndex(where: { $0.id == highlightedId }),
           highlightedIndex != 0 {
            let highlighted = photos.remove(at: highlightedIndex)
            photos.insert(highlighted, at: 0)
        }
        return photos
    }

    var body: some View {
        if workout.photos.count == 1, let photo = workout.photos.first {
            // Single photo/video - full width
            SingleMediaView(photo: photo)
        } else {
            // Multiple photos/videos - horizontal carousel
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sortedPhotos) { photo in
                        CarouselMediaThumbnail(photo: photo)
                    }
                }
            }
        }
    }
}

/// Full-width single media view with autoplay video support
struct SingleMediaView: View {
    let photo: Photo

    @State private var loadedImage: UIImage?
    @State private var isLoading = true
    @State private var isVisible = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if photo.isVideo {
                    AutoPlayVideoView(photo: photo, isVisible: $isVisible)
                } else if let image = loadedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else if isLoading {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundStyle(.gray)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
        }
        .frame(height: 220)
        .task {
            if !photo.isVideo {
                await loadPhoto()
            }
        }
    }

    private func loadPhoto() async {
        // Check cache first
        if let cached = ImageCache.shared.image(for: photo.url) {
            await MainActor.run {
                self.loadedImage = cached
                self.isLoading = false
            }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: photo.url)
            await MainActor.run {
                if let image = UIImage(data: data) {
                    ImageCache.shared.store(image, for: photo.url)
                    self.loadedImage = image
                }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}

/// Auto-playing video view that plays when visible and resets when not
struct AutoPlayVideoView: View {
    let photo: Photo
    @Binding var isVisible: Bool

    @State private var player: AVPlayer?
    @State private var thumbnail: UIImage?
    @State private var isLoading = true
    @State private var loopObserver: NSObjectProtocol?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let player = player {
                    VideoPlayerView(player: player)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .onChange(of: isVisible) { _, visible in
                            if visible {
                                player.seek(to: .zero)
                                player.play()
                            } else {
                                player.pause()
                                player.seek(to: .zero)
                            }
                        }
                } else if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .overlay {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                        }
                } else if isLoading {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                }

                // Duration badge
                if let duration = photo.duration {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(formatVideoDuration(duration))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.7))
                                )
                                .padding(8)
                        }
                    }
                }
            }
        }
        .task {
            await loadVideo()
        }
        .onDisappear {
            player?.pause()
            if let observer = loopObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            loopObserver = nil
            player = nil
        }
    }

    private func loadVideo() async {
        // First check cache for thumbnail
        if let cached = ImageCache.shared.image(for: photo.url) {
            await MainActor.run {
                self.thumbnail = cached
            }
        } else {
            // Load thumbnail
            let asset = AVURLAsset(url: photo.url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true

            do {
                let cgImage = try await imageGenerator.image(at: .zero).image
                let image = UIImage(cgImage: cgImage)
                await MainActor.run {
                    ImageCache.shared.store(image, for: photo.url)
                    self.thumbnail = image
                }
            } catch {
                print("Failed to generate thumbnail: \(error)")
            }
        }

        // Then set up player
        let newPlayer = AVPlayer(url: photo.url)
        newPlayer.isMuted = true
        newPlayer.actionAtItemEnd = .none

        // Loop video - store observer token for cleanup
        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: newPlayer.currentItem,
            queue: .main
        ) { [weak newPlayer] _ in
            newPlayer?.seek(to: .zero)
            newPlayer?.play()
        }

        await MainActor.run {
            self.loopObserver = observer
            self.player = newPlayer
            self.isLoading = false
            if isVisible {
                newPlayer.play()
            }
        }
    }

    private func formatVideoDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Simple AVPlayer wrapper view
struct VideoPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> UIView {
        let view = PlayerUIView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    class PlayerUIView: UIView {
        var player: AVPlayer? {
            didSet {
                playerLayer.player = player
            }
        }

        private var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }

        override static var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.videoGravity = .resizeAspectFill
        }
    }
}

/// Carousel thumbnail for multiple media
struct CarouselMediaThumbnail: View {
    let photo: Photo

    @State private var loadedImage: UIImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 140, height: 140)
                    .clipped()

                // Video overlay
                if photo.isVideo {
                    ZStack {
                        Color.black.opacity(0.2)

                        VStack {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white)

                            if let duration = photo.duration {
                                Text(formatDuration(duration))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(Color.black.opacity(0.6))
                                    )
                            }
                        }
                    }
                }
            } else if isLoading {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 140, height: 140)
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 140, height: 140)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 16))
                            .foregroundStyle(.gray)
                    }
            }
        }
        .frame(width: 140, height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task {
            await loadMedia()
        }
    }

    private func loadMedia() async {
        if photo.isVideo {
            await loadVideoThumbnail()
        } else {
            await loadPhoto()
        }
    }

    private func loadPhoto() async {
        // Check cache first
        if let cached = ImageCache.shared.image(for: photo.url) {
            await MainActor.run {
                self.loadedImage = cached
                self.isLoading = false
            }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: photo.url)
            await MainActor.run {
                if let image = UIImage(data: data) {
                    ImageCache.shared.store(image, for: photo.url)
                    self.loadedImage = image
                }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }

    private func loadVideoThumbnail() async {
        // Check cache first
        if let cached = ImageCache.shared.image(for: photo.url) {
            await MainActor.run {
                self.loadedImage = cached
                self.isLoading = false
            }
            return
        }

        let asset = AVURLAsset(url: photo.url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        do {
            let cgImage = try await imageGenerator.image(at: .zero).image
            let image = UIImage(cgImage: cgImage)
            await MainActor.run {
                ImageCache.shared.store(image, for: photo.url)
                self.loadedImage = image
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// A compact thumbnail view for displaying the highlighted photo/video on workout cards
struct HighlightedPhotoThumbnail: View {
    let photo: Photo
    
    @State private var loadedImage: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = loadedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                    
                    // Video overlay
                    if photo.isVideo {
                        ZStack {
                            Color.black.opacity(0.2)
                            
                            HStack(spacing: 6) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.white)
                                
                                if let duration = photo.duration {
                                    Text(formatDuration(duration))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(Color.black.opacity(0.6))
                                        )
                                }
                            }
                        }
                    }
                } else if isLoading {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundStyle(.gray)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(height: 260)
        .task {
            await loadMedia()
        }
    }
    
    private func loadMedia() async {
        if photo.isVideo {
            await loadVideoThumbnail()
        } else {
            await loadPhoto()
        }
    }
    
    private func loadPhoto() async {
        // Check cache first
        if let cached = ImageCache.shared.image(for: photo.url) {
            await MainActor.run {
                self.loadedImage = cached
                self.isLoading = false
            }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: photo.url)
            await MainActor.run {
                if let image = UIImage(data: data) {
                    ImageCache.shared.store(image, for: photo.url)
                    self.loadedImage = image
                }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }

    private func loadVideoThumbnail() async {
        // Check cache first
        if let cached = ImageCache.shared.image(for: photo.url) {
            await MainActor.run {
                self.loadedImage = cached
                self.isLoading = false
            }
            return
        }

        do {
            let asset = AVURLAsset(url: photo.url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true

            let cgImage = try await imageGenerator.image(at: .zero).image
            let image = UIImage(cgImage: cgImage)

            await MainActor.run {
                ImageCache.shared.store(image, for: photo.url)
                self.loadedImage = image
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "0:%02d", seconds)
        }
    }
}

#Preview {
    NavigationStack {
        WorkoutListView()
    }
    .modelContainer(for: Workout.self, inMemory: true)
}
