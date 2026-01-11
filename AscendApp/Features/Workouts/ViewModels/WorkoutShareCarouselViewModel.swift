//
//  WorkoutShareCarouselViewModel.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/26/25.
//

import Foundation
import SwiftUI
import UIKit
import AVFoundation

/// Theme options for shareable cards
enum ShareCardTheme: String, CaseIterable {
    case dark
    case light
    
    var backgroundColor: Color {
        switch self {
        case .dark:
            return .clear // Uses gradient
        case .light:
            return .white
        }
    }
    
    var textColor: Color {
        switch self {
        case .dark:
            return .white
        case .light:
            return .black
        }
    }
    
    var secondaryTextColor: Color {
        switch self {
        case .dark:
            return .white.opacity(0.7)
        case .light:
            return .gray
        }
    }
}

/// Types of cards available in the carousel
enum ShareCardType: Identifiable, Equatable {
    case photoMedia(photoId: UUID)
    case template(templateId: String)
    case detailedSummary

    var id: String {
        switch self {
        case .photoMedia(let photoId): return "photoMedia_\(photoId.uuidString)"
        case .template(let templateId): return "template_\(templateId)"
        case .detailedSummary: return "detailedSummary"
        }
    }

    /// Whether this card type supports theme toggling
    var supportsThemeToggle: Bool {
        switch self {
        case .photoMedia, .template:
            return false
        case .detailedSummary:
            return true
        }
    }

    /// Returns the photo ID if this is a photo card
    var photoId: UUID? {
        switch self {
        case .photoMedia(let photoId): return photoId
        case .template, .detailedSummary: return nil
        }
    }

    /// Returns the template ID if this is a template card
    var templateId: String? {
        switch self {
        case .template(let templateId): return templateId
        case .photoMedia, .detailedSummary: return nil
        }
    }
}

@MainActor
final class WorkoutShareCarouselViewModel: ObservableObject {
    // MARK: - Constants
    static let posterExportSize = CGSize(width: 1080, height: 1350)
    static let posterAspectRatio = posterExportSize.width / posterExportSize.height
    static let displayCardHeight: CGFloat = 460
    static let displayCardWidth: CGFloat = displayCardHeight * posterAspectRatio
    
    // MARK: - Published Properties
    @Published var currentCardIndex: Int = 0
    @Published var cardTheme: ShareCardTheme = .dark
    @Published var isLoadingPhotos: Bool = false
    @Published var photoImages: [UUID: UIImage] = [:]
    @Published var templateImages: [String: UIImage] = [:]
    @Published var copyConfirmationText: String?
    @Published var shareErrorMessage: String?

    // MARK: - Strava Sync State
    @Published var stravaSyncState: StravaSyncState = .idle

    enum StravaSyncState {
        case idle
        case syncing
        case synced
        case error(String)
    }

    // MARK: - Properties
    let workout: Workout
    let workoutCount: Int?
    let displayName: String
    var availableCards: [ShareCardType]
    private var photoLoadTasks: [Task<Void, Never>] = []
    private let templateService = ShareCardTemplateService.shared
    
    // MARK: - Computed Properties
    var currentCardType: ShareCardType {
        guard currentCardIndex < availableCards.count else {
            return availableCards.first ?? .detailedSummary
        }
        return availableCards[currentCardIndex]
    }
    
    var canToggleTheme: Bool {
        currentCardType.supportsThemeToggle
    }

    var hasPhotos: Bool {
        !workout.photos.isEmpty
    }

    /// Returns the image for the current photo card (if applicable)
    var currentPhotoImage: UIImage? {
        guard let photoId = currentCardType.photoId else { return nil }
        return photoImages[photoId]
    }

    /// Returns the image for the current template card (if applicable)
    var currentTemplateImage: UIImage? {
        guard let templateId = currentCardType.templateId else { return nil }
        return templateImages[templateId]
    }
    
    // MARK: - Initialization

    /// Initialize for workout completion flow
    init(workout: Workout, workoutCount: Int, displayName: String) {
        self.workout = workout
        self.workoutCount = workoutCount
        self.displayName = displayName
        self.availableCards = Self.determineAvailableCards(for: workout, templates: [])
        preloadAllPhotos()
        loadTemplateCards()
    }

    /// Initialize for share flow (no workout count)
    init(workout: Workout, displayName: String) {
        self.workout = workout
        self.workoutCount = nil
        self.displayName = displayName
        self.availableCards = Self.determineAvailableCards(for: workout, templates: [])
        preloadAllPhotos()
        loadTemplateCards()
    }
    
    // MARK: - Card Logic

    private static func determineAvailableCards(
        for workout: Workout,
        templates: [ShareCardTemplate]
    ) -> [ShareCardType] {
        var cards: [ShareCardType] = []

        // 1. Add user's photos (highlighted first, then rest)
        var orderedPhotos = workout.photos
        if let highlightedId = workout.highlightedPhotoId,
           let highlightedIndex = orderedPhotos.firstIndex(where: { $0.id == highlightedId }),
           highlightedIndex != 0 {
            let highlighted = orderedPhotos.remove(at: highlightedIndex)
            orderedPhotos.insert(highlighted, at: 0)
        }

        for photo in orderedPhotos {
            cards.append(.photoMedia(photoId: photo.id))
        }

        // 2. Add template cards
        for template in templates {
            cards.append(.template(templateId: template.id))
        }

        // 3. Always include detailed summary last
        cards.append(.detailedSummary)

        return cards
    }

    /// Load template cards from the template service
    private func loadTemplateCards() {
        Task {
            // Wait for the service to finish loading (poll until done or timeout)
            var attempts = 0
            let maxAttempts = 50 // 5 seconds max (50 * 100ms)

            while templateService.isLoading && attempts < maxAttempts {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                attempts += 1
            }

            print("📸 ViewModel: Service finished loading after \(attempts * 100)ms")

            let templates = templateService.loadedTemplates
            let images = templateService.loadedTemplateImages

            print("📸 ViewModel: Found \(templates.count) templates, \(images.count) images from service")

            // Update template images
            self.templateImages = images

            // Rebuild available cards with templates
            self.availableCards = Self.determineAvailableCards(
                for: workout,
                templates: templates
            )

            print("📸 ViewModel: availableCards now has \(self.availableCards.count) cards")
        }
    }
    
    // MARK: - Theme
    
    func toggleTheme() {
        guard canToggleTheme else { return }
        cardTheme = cardTheme == .dark ? .light : .dark
        HapticsManager.shared.trigger(.lightImpact)
    }
    
    // MARK: - Photo Loading

    private func preloadAllPhotos() {
        guard !workout.photos.isEmpty else { return }

        var needsLoading = false
        for photo in workout.photos {
            // Check cache first
            if let cached = ImageCache.shared.image(for: photo.url) {
                photoImages[photo.id] = cached
            } else {
                needsLoading = true
            }
        }

        // If all images were cached, we're done
        if photoImages.count == workout.photos.count {
            return
        }

        isLoadingPhotos = true

        for photo in workout.photos {
            // Skip if already loaded from cache
            if photoImages[photo.id] != nil { continue }

            let task = Task { [weak self] in
                let image: UIImage?

                if photo.isVideo {
                    // Extract thumbnail from video at 25%
                    image = await Self.extractVideoThumbnail(from: photo.url)
                } else {
                    // Load image normally
                    image = await Self.loadImage(from: photo.url)
                }

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self?.photoImages[photo.id] = image
                    // Check if all photos are loaded
                    if self?.photoImages.count == self?.workout.photos.count {
                        self?.isLoadingPhotos = false
                    }
                }
            }
            photoLoadTasks.append(task)
        }
    }

    private static func loadImage(from url: URL) async -> UIImage? {
        // Check cache first
        if let cached = ImageCache.shared.image(for: url) {
            return cached
        }

        return await Task.detached(priority: .utility) { () -> UIImage? in
            do {
                let data: Data
                if url.isFileURL {
                    data = try Data(contentsOf: url)
                } else {
                    let (remoteData, _) = try await URLSession.shared.data(from: url)
                    data = remoteData
                }
                if let image = UIImage(data: data) {
                    // Store in cache
                    await MainActor.run {
                        ImageCache.shared.store(image, for: url)
                    }
                    return image
                }
                return nil
            } catch {
                return nil
            }
        }.value
    }

    private static func extractVideoThumbnail(from url: URL) async -> UIImage? {
        // Check cache first (video thumbnails are cached by video URL)
        if let cached = ImageCache.shared.image(for: url) {
            return cached
        }

        return await Task.detached(priority: .utility) { () -> UIImage? in
            let asset = AVURLAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 1080, height: 1350) // Match poster export size

            do {
                // Get duration and extract thumbnail at 25%
                let duration = try await asset.load(.duration)
                let targetTime = CMTime(
                    seconds: duration.seconds * 0.25,
                    preferredTimescale: 600
                )
                let cgImage = try imageGenerator.copyCGImage(at: targetTime, actualTime: nil)
                let image = UIImage(cgImage: cgImage)
                // Store in cache
                await MainActor.run {
                    ImageCache.shared.store(image, for: url)
                }
                return image
            } catch {
                print("Failed to extract video thumbnail: \(error)")
                return nil
            }
        }.value
    }
    
    // MARK: - Rendering
    
    func renderCurrentCard(
        measurementSystem: MeasurementSystem,
        stepHeight: Double,
        preferredMetric: WorkoutMetric
    ) -> UIImage? {
        let cardView = currentCardView(
            measurementSystem: measurementSystem,
            stepHeight: stepHeight,
            preferredMetric: preferredMetric
        )
        
        let content = cardView
            .frame(width: Self.displayCardWidth, height: Self.displayCardHeight)
            .clipped()
        
        let renderer = ImageRenderer(content: content)
        renderer.scale = Self.posterExportSize.height / Self.displayCardHeight
        return renderer.uiImage
    }
    
    @ViewBuilder
    func currentCardView(
        measurementSystem: MeasurementSystem,
        stepHeight: Double,
        preferredMetric: WorkoutMetric
    ) -> some View {
        switch currentCardType {
        case .photoMedia(let photoId):
            PhotoMediaCard(
                workout: workout,
                image: photoImages[photoId],
                measurementSystem: measurementSystem,
                stepHeight: stepHeight,
                preferredMetric: preferredMetric,
                displayName: displayName
            )
        case .template(let templateId):
            TemplateMediaCard(
                workout: workout,
                image: templateImages[templateId],
                measurementSystem: measurementSystem,
                stepHeight: stepHeight,
                preferredMetric: preferredMetric,
                displayName: displayName
            )
        case .detailedSummary:
            DetailedSummaryCard(
                workout: workout,
                theme: cardTheme,
                measurementSystem: measurementSystem,
                stepHeight: stepHeight,
                preferredMetric: preferredMetric,
                displayName: displayName
            )
        }
    }
    
    // MARK: - Share Text
    
    func shareText(
        measurementSystem: MeasurementSystem,
        stepHeight: Double,
        preferredMetric: WorkoutMetric
    ) -> String {
        workoutShareText(
            for: workout,
            measurementSystem: measurementSystem,
            stepHeight: stepHeight,
            preferredMetric: preferredMetric
        )
    }
    
    // MARK: - Copy Text
    
    func copyShareText(
        measurementSystem: MeasurementSystem,
        stepHeight: Double,
        preferredMetric: WorkoutMetric
    ) {
        UIPasteboard.general.string = shareText(
            measurementSystem: measurementSystem,
            stepHeight: stepHeight,
            preferredMetric: preferredMetric
        )
        showCopyConfirmation("Copied!")
    }
    
    func showCopyConfirmation(_ text: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            copyConfirmationText = text
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            withAnimation(.easeOut(duration: 0.3)) {
                self?.copyConfirmationText = nil
            }
        }
    }

    // MARK: - Strava Sync

    /// Whether to show the manual Strava sync button
    /// Shows only when: feature enabled, connected, auto-sync disabled, and workout not already synced
    var shouldShowStravaSyncButton: Bool {
        guard FeatureFlags.isStravaEnabled else { return false }
        let stravaManager = StravaManager.shared
        return stravaManager.isConnected &&
               !stravaManager.autoSyncEnabled &&
               !workout.isSyncedToStrava
    }

    /// Sync the workout to Strava
    func syncToStrava(preferredMetric: WorkoutMetric) {
        guard case .idle = stravaSyncState else { return }

        stravaSyncState = .syncing
        HapticsManager.shared.trigger(.lightImpact)

        Task {
            do {
                let activityId = try await StravaManager.shared.syncWorkout(workout, primaryMetric: preferredMetric)
                workout.setStravaSyncMetadata(StravaSyncMetadata(stravaActivityId: activityId, syncedAt: Date()))

                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    stravaSyncState = .synced
                }
                HapticsManager.shared.trigger(.success)
            } catch {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    stravaSyncState = .error(error.localizedDescription)
                }
                HapticsManager.shared.trigger(.error)

                // Reset to idle after a delay so user can try again
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    if case .error = self?.stravaSyncState {
                        withAnimation {
                            self?.stravaSyncState = .idle
                        }
                    }
                }
            }
        }
    }

    // MARK: - Cleanup

    deinit {
        for task in photoLoadTasks {
            task.cancel()
        }
    }
}

