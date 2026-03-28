//
//  WorkoutShareCarouselViewModel.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/26/25.
//

import Foundation
import SwiftUI
import UIKit

/// Types of cards available in the carousel.
/// v1 ships a single bundled poster card while keeping the carousel shell in place.
enum ShareCardType: Identifiable, Equatable {
    case poster

    var id: String {
        switch self {
        case .poster:
            return "poster"
        }
    }

    var preset: WorkoutShareCardPreset {
        switch self {
        case .poster:
            return .defaultSquarePoster
        }
    }
}

@MainActor
@Observable
final class WorkoutShareCarouselViewModel {
    static let posterExportSize = CGSize(width: 1080, height: 1080)
    static let displayCardSize: CGFloat = 344
    static let displayCardWidth: CGFloat = displayCardSize
    static let displayCardHeight: CGFloat = displayCardSize

    var currentCardIndex: Int = 0
    var copyConfirmationText: String?
    var shareErrorMessage: String?
    var stravaSyncState: StravaSyncState = .idle

    enum StravaSyncState {
        case idle
        case syncing
        case synced
        case error(String)
    }

    let workout: Workout
    let workoutCount: Int?
    let availableCards: [ShareCardType] = [.poster]

    private let composer = WorkoutShareCardComposer()

    var currentCardType: ShareCardType {
        guard currentCardIndex < availableCards.count else {
            return .poster
        }
        return availableCards[currentCardIndex]
    }

    init(workout: Workout, workoutCount: Int) {
        self.workout = workout
        self.workoutCount = workoutCount
    }

    init(workout: Workout) {
        self.workout = workout
        self.workoutCount = nil
    }

    func composition(
        for cardType: ShareCardType,
        measurementSystem: MeasurementSystem,
        stepHeight: Double,
        preferredMetric: WorkoutMetric
    ) -> WorkoutShareCardComposition {
        composer.compose(
            workout: workout,
            measurementSystem: measurementSystem,
            stepHeight: stepHeight,
            preferredMetric: preferredMetric,
            preset: cardType.preset
        )
    }

    func renderCurrentCard(
        measurementSystem: MeasurementSystem,
        stepHeight: Double,
        preferredMetric: WorkoutMetric
    ) -> UIImage? {
        let content = currentCardView(
            measurementSystem: measurementSystem,
            stepHeight: stepHeight,
            preferredMetric: preferredMetric
        )
        .frame(width: Self.displayCardWidth, height: Self.displayCardHeight)

        let renderer = ImageRenderer(content: content)
        renderer.scale = Self.posterExportSize.width / Self.displayCardWidth
        renderer.isOpaque = false
        return renderer.uiImage
    }

    @ViewBuilder
    func currentCardView(
        measurementSystem: MeasurementSystem,
        stepHeight: Double,
        preferredMetric: WorkoutMetric
    ) -> some View {
        cardView(
            for: currentCardType,
            measurementSystem: measurementSystem,
            stepHeight: stepHeight,
            preferredMetric: preferredMetric
        )
    }

    @ViewBuilder
    func cardView(
        for cardType: ShareCardType,
        measurementSystem: MeasurementSystem,
        stepHeight: Double,
        preferredMetric: WorkoutMetric
    ) -> some View {
        switch cardType {
        case .poster:
            WorkoutSquareShareCard(
                composition: composition(
                    for: cardType,
                    measurementSystem: measurementSystem,
                    stepHeight: stepHeight,
                    preferredMetric: preferredMetric
                )
            )
        }
    }

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

        Task {
            try await Task.sleep(for: .milliseconds(1600))
            withAnimation(.easeOut(duration: 0.3)) {
                copyConfirmationText = nil
            }
        }
    }

    /// Whether to show the manual Strava sync button.
    /// Shows only when: feature enabled, connected, auto-sync disabled, and workout not already synced.
    var shouldShowStravaSyncButton: Bool {
        guard FeatureFlags.isStravaEnabled else { return false }
        let stravaManager = StravaManager.shared
        return stravaManager.isConnected &&
            !stravaManager.autoSyncEnabled &&
            !workout.isSyncedToStrava
    }

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

                try? await Task.sleep(for: .seconds(2))
                if case .error = stravaSyncState {
                    withAnimation {
                        stravaSyncState = .idle
                    }
                }
            }
        }
    }
}
