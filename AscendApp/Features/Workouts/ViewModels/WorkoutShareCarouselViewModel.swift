//
//  WorkoutShareCarouselViewModel.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/26/25.
//

import Foundation
import SwiftUI
import UIKit

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
    case photoMedia
    case detailedSummary
    case verticalClimbFunFact
    
    var id: String {
        switch self {
        case .photoMedia: return "photoMedia"
        case .detailedSummary: return "detailedSummary"
        case .verticalClimbFunFact: return "verticalClimbFunFact"
        }
    }
    
    /// Whether this card type supports theme toggling
    var supportsThemeToggle: Bool {
        switch self {
        case .photoMedia:
            return false
        case .detailedSummary, .verticalClimbFunFact:
            return true
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
    @Published var isLoadingPhoto: Bool = false
    @Published var photoImage: UIImage?
    @Published var copyConfirmationText: String?
    @Published var shareErrorMessage: String?
    
    // MARK: - Properties
    let workout: Workout
    let workoutCount: Int?
    let displayName: String
    let availableCards: [ShareCardType]
    private var photoLoadTask: Task<Void, Never>?
    
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
    
    var hasPhoto: Bool {
        workout.highlightedPhoto != nil
    }
    
    // MARK: - Initialization
    
    /// Initialize for workout completion flow
    init(workout: Workout, workoutCount: Int, displayName: String) {
        self.workout = workout
        self.workoutCount = workoutCount
        self.displayName = displayName
        self.availableCards = Self.determineAvailableCards(for: workout)
        preloadPhotoIfNeeded()
    }
    
    /// Initialize for share flow (no workout count)
    init(workout: Workout, displayName: String) {
        self.workout = workout
        self.workoutCount = nil
        self.displayName = displayName
        self.availableCards = Self.determineAvailableCards(for: workout)
        preloadPhotoIfNeeded()
    }
    
    // MARK: - Card Logic
    
    private static func determineAvailableCards(for workout: Workout) -> [ShareCardType] {
        var cards: [ShareCardType] = []
        
        // Photo card only if workout has media
        if workout.highlightedPhoto != nil {
            cards.append(.photoMedia)
        }
        
        // Always include detailed summary
        cards.append(.detailedSummary)
        
        // Fun fact card only if we have steps (for vertical climb calculation)
        if workout.steps > 0 {
            cards.append(.verticalClimbFunFact)
        }
        
        return cards
    }
    
    // MARK: - Theme
    
    func toggleTheme() {
        guard canToggleTheme else { return }
        cardTheme = cardTheme == .dark ? .light : .dark
        HapticsManager.shared.trigger(.lightImpact)
    }
    
    // MARK: - Photo Loading
    
    private func preloadPhotoIfNeeded() {
        guard let photo = workout.highlightedPhoto else { return }
        loadPhoto(from: photo.url)
    }
    
    private func loadPhoto(from url: URL) {
        photoLoadTask?.cancel()
        isLoadingPhoto = true
        
        photoLoadTask = Task { [weak self] in
            let image = await Self.loadImage(from: url)
            
            guard !Task.isCancelled else {
                await MainActor.run {
                    self?.isLoadingPhoto = false
                }
                return
            }
            
            await MainActor.run {
                self?.photoImage = image
                self?.isLoadingPhoto = false
            }
        }
    }
    
    private static func loadImage(from url: URL) async -> UIImage? {
        await Task.detached(priority: .utility) { () -> UIImage? in
            do {
                let data: Data
                if url.isFileURL {
                    data = try Data(contentsOf: url)
                } else {
                    let (remoteData, _) = try await URLSession.shared.data(from: url)
                    data = remoteData
                }
                return UIImage(data: data)
            } catch {
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
        case .photoMedia:
            PhotoMediaCard(
                workout: workout,
                image: photoImage,
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
        case .verticalClimbFunFact:
            VerticalClimbFunFactCard(
                workout: workout,
                theme: cardTheme,
                measurementSystem: measurementSystem,
                stepHeight: stepHeight,
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
    
    // MARK: - Cleanup
    
    deinit {
        photoLoadTask?.cancel()
    }
}

